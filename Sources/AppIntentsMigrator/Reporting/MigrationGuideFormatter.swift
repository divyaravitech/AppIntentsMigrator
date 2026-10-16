import Foundation

/// Renders migration suggestions as a readable console guide.
enum MigrationGuideFormatter {

    private static let width = 78
    private static let indent = "    "

    /// A grouped migration guide: one section per distinct migration, listing every
    /// place it applies, with before/after code, rationale, complexity, and docs.
    static func formatSuggestions(suggestions: [MigrationSuggestion]) -> String {
        guard !suggestions.isEmpty else {
            return """
            App Intents Migration Guide
            \(String(repeating: "=", count: width))

            No SiriKit patterns detected — nothing to migrate.
            """
        }

        let groups = SuggestionGenerator().groupedByMigration(suggestions)
        let autoPatchable = suggestions.filter { $0.complexity == .autoPatchable }.count
        let manualReview = suggestions.count - autoPatchable

        var lines: [String] = []
        lines.append("App Intents Migration Guide")
        lines.append(String(repeating: "=", count: width))
        lines.append("Suggestions:         \(suggestions.count)")
        lines.append("Distinct migrations: \(groups.count)")
        lines.append("Auto-patchable:      \(autoPatchable)")
        lines.append("Manual review:       \(manualReview)")

        for (index, group) in groups.enumerated() {
            lines.append(contentsOf: section(for: group, index: index + 1, of: groups.count))
        }

        lines.append("")
        lines.append(String(repeating: "=", count: width))
        lines.append("Start with the \(autoPatchable) auto-patchable occurrence(s); they are mechanical.")

        return lines.joined(separator: "\n")
    }

    private static func section(for group: MigrationGroup, index: Int, of total: Int) -> [String] {
        let suggestion = group.representative
        var lines: [String] = []

        lines.append("")
        lines.append(String(repeating: "-", count: width))
        lines.append("[\(index)/\(total)]  \(group.title)")
        lines.append(String(repeating: "-", count: width))
        lines.append("Pattern:     \(group.patternType.rawValue) — \(suggestion.pattern.rule.rawValue)")
        lines.append("Complexity:  \(group.complexity.displayLabel)")
        lines.append("Apple docs:  \(suggestion.appleDocLink)")
        lines.append("Occurrences: \(group.occurrences)")
        for location in group.locations {
            lines.append("  • \(location.file):\(location.line)  \(truncate(location.code))")
        }

        lines.append("")
        lines.append(heading("BEFORE (SiriKit)"))
        lines.append(contentsOf: indented(suggestion.beforeCode))

        lines.append("")
        lines.append(heading("AFTER (App Intents)"))
        lines.append(contentsOf: indented(suggestion.afterCode))

        lines.append("")
        lines.append(heading("WHY"))
        lines.append(contentsOf: wrap(suggestion.explanation, to: width - indent.count).map { indent + $0 })

        return lines
    }

    // MARK: - Patch reports

    /// A patch report: what changed (or would change), line by line, plus what was skipped.
    static func formatPatchResult(
        _ result: PatchResult,
        mode: AutoPatcher.Mode,
        validationMode: SyntaxValidator.Mode
    ) -> String {
        var lines: [String] = []

        let title = mode == .dryRun
            ? "App Intents Auto-Patcher — DRY RUN (nothing written)"
            : "App Intents Auto-Patcher"
        lines.append(title)
        lines.append(String(repeating: "=", count: width))
        lines.append("Files patched:  \(result.filesPatched)")
        lines.append("Lines changed:  \(result.linesChanged)")
        lines.append("Skipped:        \(result.skipped.count)")
        lines.append("Validation:     \(result.validated ? "passed" : "FAILED") (swiftc -\(validationMode.rawValue))")
        if let backup = result.backup {
            lines.append("Backup:         \((backup.path as NSString).lastPathComponent) (\(backup.fileCount) files)")
        }

        if !result.edits.isEmpty {
            lines.append("")
            lines.append(mode == .dryRun ? "CHANGES THAT WOULD BE MADE" : "CHANGES")
            lines.append(String(repeating: "-", count: width))
            for edit in result.edits.sorted(by: { ($0.file, $0.line) < ($1.file, $1.line) }) {
                lines.append("\(edit.file):\(edit.line)  [\(edit.safety.displayLabel) \(edit.patchRuleID)]")
                lines.append("  - \(edit.before.trimmingCharacters(in: .whitespaces))")
                if let after = edit.after {
                    lines.append("  + \(after.trimmingCharacters(in: .whitespaces))")
                } else {
                    lines.append("  + (line removed)")
                }
                lines.append("")
            }
        }

        if !result.validationErrors.isEmpty {
            lines.append("VALIDATION ERRORS — changes were not kept")
            lines.append(String(repeating: "-", count: width))
            for error in result.validationErrors {
                lines.append("  \(error.file):\(error.line)  \(error.error)")
            }
            lines.append("")
        }

        if !result.skipped.isEmpty {
            lines.append("SKIPPED (\(result.skipped.count)) — migrate these by hand, see `suggest`")
            lines.append(String(repeating: "-", count: width))
            for reason in result.skipped.sorted() {
                lines.append("  \(reason)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// A standalone validation report, for `--validate-only`.
    static func formatValidation(_ errors: [ValidationError], fileCount: Int, mode: SyntaxValidator.Mode) -> String {
        var lines: [String] = []
        lines.append("Swift Validation (swiftc -\(mode.rawValue))")
        lines.append(String(repeating: "=", count: width))
        lines.append("Files checked:  \(fileCount)")
        lines.append("Files failing:  \(Set(errors.map(\.file)).count)")
        lines.append("Errors:         \(errors.count)")

        if errors.isEmpty {
            lines.append("")
            lines.append("All files parse cleanly.")
            return lines.joined(separator: "\n")
        }

        lines.append("")
        for error in errors.sorted(by: { ($0.file, $0.line) < ($1.file, $1.line) }) {
            lines.append("  \(error.file):\(error.line)  \(error.error)")
        }
        return lines.joined(separator: "\n")
    }

    private static func heading(_ text: String) -> String {
        let dashes = max(0, width - text.count - 4)
        return "-- \(text) \(String(repeating: "-", count: dashes))"
    }

    private static func indented(_ code: String) -> [String] {
        code.split(separator: "\n", omittingEmptySubsequences: false).map { indent + $0 }
    }

    /// Shortens a source line so the occurrence list stays on one row.
    private static func truncate(_ code: String, limit: Int = 56) -> String {
        code.count <= limit ? code : String(code.prefix(limit - 1)) + "…"
    }

    /// Greedy word wrap. Words longer than `limit` are left intact rather than split.
    private static func wrap(_ text: String, to limit: Int) -> [String] {
        var lines: [String] = []
        var current = ""

        for word in text.split(whereSeparator: \.isWhitespace) {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= limit {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
