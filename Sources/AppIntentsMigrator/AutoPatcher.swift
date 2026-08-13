import Foundation

/// Applies safe SiriKit → App Intents rewrites, with a backup and a validation gate.
///
/// Safety model, in order:
/// 1. `patchProject` archives every Swift file before writing anything.
/// 2. A file is only written if its patched contents still parse — validation happens on a
///    temporary copy first, so an invalid patch is never committed to the working tree.
/// 3. After all writes, the patched set is validated again; any failure restores the backup.
/// 4. Structural rewrites are excluded unless the caller opts in via `allowProposals`.
///
/// The actor serialises patching, so concurrent callers cannot interleave writes to the
/// same file.
actor AutoPatcher {

    enum Mode: String, Sendable {
        /// Compute and validate changes, write nothing.
        case dryRun
        /// Write changes that pass validation.
        case apply
    }

    let mode: Mode
    /// When true, structural (`.proposalOnly`) rules are applied too. Off by default.
    let allowProposals: Bool

    private let validator: SyntaxValidator
    private let backupManager = BackupManager()

    init(mode: Mode = .dryRun, validation: SyntaxValidator.Mode = .parse, allowProposals: Bool = false) {
        self.mode = mode
        self.allowProposals = allowProposals
        self.validator = SyntaxValidator(mode: validation)
    }

    // MARK: - Single file

    /// Patches one file using the suggestions that apply to it.
    ///
    /// The file is written only in `.apply` mode and only when the patched text validates.
    /// This method does not take a backup — `patchProject` does that once for the whole
    /// project. Calling it directly cannot corrupt a file (an invalid result is discarded),
    /// but it also cannot restore a previous version.
    ///
    /// - Parameters:
    ///   - file: Absolute path to the Swift file.
    ///   - suggestions: Suggestions whose `pattern.line` refers to this file.
    func patchFile(_ file: String, using suggestions: [MigrationSuggestion]) async throws -> PatchResult {
        let url = URL(fileURLWithPath: file)
        guard let original = try? String(contentsOf: url, encoding: .utf8) else {
            return PatchResult(
                filesPatched: 0,
                linesChanged: 0,
                skipped: ["\(file) — could not be read as UTF-8"],
                validated: true
            )
        }

        let plan = plan(for: original, displayPath: suggestions.first?.pattern.file ?? file, suggestions: suggestions)
        guard !plan.edits.isEmpty else {
            return PatchResult(filesPatched: 0, linesChanged: 0, skipped: plan.skipped, validated: true)
        }

        // Validate the would-be result before it touches the working tree. This runs in
        // dry-run mode too, so `--dry-run` reports whether the patch would still parse.
        let errors = try await validate(contents: plan.patched, representing: file)
        guard errors.isEmpty else {
            return PatchResult(
                filesPatched: 0,
                linesChanged: 0,
                skipped: plan.skipped,
                validated: false,
                edits: plan.edits,
                validationErrors: errors
            )
        }

        if mode == .apply {
            try Data(plan.patched.utf8).write(to: url, options: .atomic)
        }

        return PatchResult(
            filesPatched: 1,
            linesChanged: plan.edits.count,
            skipped: plan.skipped,
            validated: true,
            edits: plan.edits
        )
    }

    // MARK: - Whole project

    /// Patches every file with suggestions, backing the project up first.
    ///
    /// - Throws: `PatchError.backupFailed` before any write if the archive cannot be made;
    ///   `PatchError.rollbackFailed` if a restore is needed but does not succeed.
    func patchProject(
        root: String,
        suggestions: [MigrationSuggestion]
    ) async throws -> PatchResult {
        let byFile = Dictionary(grouping: suggestions, by: \.pattern.file)
        guard !byFile.isEmpty else {
            return PatchResult(filesPatched: 0, linesChanged: 0, skipped: [], validated: true)
        }

        // Requirement: always back up before modifying anything.
        var backup: BackupInfo?
        if mode == .apply {
            backup = try await backupManager.createBackup(projectPath: root)
        }

        var filesPatched = 0
        var linesChanged = 0
        var skipped: [String] = []
        var edits: [PatchEdit] = []
        var validationErrors: [ValidationError] = []
        var writtenFiles: [String] = []

        for (relativePath, fileSuggestions) in byFile.sorted(by: { $0.key < $1.key }) {
            let absolute = absolutePath(for: relativePath, root: root)
            let result = try await patchFile(absolute, using: fileSuggestions)

            filesPatched += result.filesPatched
            linesChanged += result.linesChanged
            skipped.append(contentsOf: result.skipped)
            edits.append(contentsOf: result.edits)
            validationErrors.append(contentsOf: result.validationErrors)

            if mode == .apply, result.filesPatched > 0 { writtenFiles.append(absolute) }
        }

        // Second gate: the files were fine individually, check them as a set before finishing.
        if mode == .apply, !writtenFiles.isEmpty {
            let postWriteErrors = try await validator.validateFiles(writtenFiles)
            if !postWriteErrors.isEmpty {
                validationErrors.append(contentsOf: postWriteErrors)
                if let backup {
                    try await backupManager.restoreBackup(backup)
                }
                return PatchResult(
                    filesPatched: 0,
                    linesChanged: 0,
                    skipped: skipped,
                    validated: false,
                    edits: edits,
                    backup: backup,
                    validationErrors: validationErrors
                )
            }
        }

        return PatchResult(
            filesPatched: filesPatched,
            linesChanged: linesChanged,
            skipped: skipped,
            validated: validationErrors.isEmpty,
            edits: edits,
            backup: backup,
            validationErrors: validationErrors
        )
    }

    /// Restores a backup archive, undoing a previous patch run.
    func rollback(archivePath: String) async throws -> BackupInfo {
        let backup = try await backupManager.backup(at: archivePath)
        try await backupManager.restoreBackup(backup)
        return backup
    }

    /// Backup archives already present in a project root, newest first.
    func availableBackups(in root: String) async -> [String] {
        await backupManager.existingBackups(in: root)
    }

    // MARK: - Planning

    private struct Plan {
        var patched: String
        var edits: [PatchEdit]
        var skipped: [String]
    }

    /// Works out the edits for one file without touching disk.
    private func plan(for contents: String, displayPath: String, suggestions: [MigrationSuggestion]) -> Plan {
        var lines = contents.components(separatedBy: "\n")
        var edits: [PatchEdit] = []
        var skipped: [String] = []
        var deletedLines = Set<Int>()

        for suggestion in suggestions.sorted(by: { $0.pattern.line < $1.pattern.line }) {
            let lineNumber = suggestion.pattern.line
            let index = lineNumber - 1
            guard lines.indices.contains(index), !deletedLines.contains(lineNumber) else { continue }

            let candidates = PatchingRules.rules(for: suggestion.pattern, allowingProposals: allowProposals)
            guard let rule = candidates.first(where: { PatchingRules.apply($0, to: lines[index]).matched }) else {
                skipped.append(skipReason(for: suggestion))
                continue
            }

            let outcome = PatchingRules.apply(rule, to: lines[index])
            edits.append(
                PatchEdit(
                    file: displayPath,
                    line: lineNumber,
                    before: lines[index],
                    after: outcome.replacement,
                    rule: suggestion.pattern.rule,
                    patchRuleID: rule.id,
                    safety: rule.safety
                )
            )

            if let replacement = outcome.replacement {
                lines[index] = replacement
            } else {
                deletedLines.insert(lineNumber)
            }
        }

        // `import Intents` and `import IntentsUI` both become `import AppIntents`; drop the
        // duplicate rather than leaving the same import twice.
        var seenAppIntentsImport = false
        for (index, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces) == "import AppIntents" {
            let lineNumber = index + 1
            guard !deletedLines.contains(lineNumber) else { continue }
            if seenAppIntentsImport {
                edits.append(
                    PatchEdit(
                        file: displayPath,
                        line: lineNumber,
                        before: line,
                        after: nil,
                        rule: .intentsImport,
                        patchRuleID: "dedupe-appintents-import",
                        safety: .automatic
                    )
                )
                deletedLines.insert(lineNumber)
            }
            seenAppIntentsImport = true
        }

        let remaining = lines.enumerated()
            .filter { !deletedLines.contains($0.offset + 1) }
            .map(\.element)

        return Plan(
            patched: remaining.joined(separator: "\n"),
            edits: edits.sorted { $0.line < $1.line },
            skipped: skipped
        )
    }

    private func skipReason(for suggestion: MigrationSuggestion) -> String {
        let location = "\(suggestion.pattern.file):\(suggestion.pattern.line)"
        let structural = PatchingRules.all.first {
            $0.rule == suggestion.pattern.rule && $0.safety == .proposalOnly
        }

        if let structural, !allowProposals {
            return "\(location) — needs a human: \(structural.summary)"
        }
        return "\(location) — no safe rewrite for \(suggestion.pattern.rule.rawValue)"
    }

    // MARK: - Validation

    /// Validates candidate file contents by parsing a temporary copy.
    private func validate(contents: String, representing file: String) async throws -> [ValidationError] {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appintents-patch-\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: temporary) }

        try Data(contents.utf8).write(to: temporary, options: .atomic)
        let result = try await validator.validateFile(temporary.path)

        // Report against the real path, not the scratch copy.
        return result.errors.map { ValidationError(file: file, line: $0.line, error: $0.error) }
    }

    private func absolutePath(for relativePath: String, root: String) -> String {
        if relativePath.hasPrefix("/") { return relativePath }
        return URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
            .appendingPathComponent(relativePath)
            .path
    }
}
