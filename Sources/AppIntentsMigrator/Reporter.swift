import Foundation

/// Renders a `ScanResult` for humans (console) and for machines (JSON).
enum Reporter {

    enum ReportError: LocalizedError {
        case cannotWriteReport(path: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .cannotWriteReport(let path, let underlying):
                return "Could not write JSON report to \(path): \((underlying as NSError).localizedDescription)"
            }
        }
    }

    /// A plain-text report: the per-type summary, then findings grouped by file.
    static func formatConsoleReport(result: ScanResult) -> String {
        var lines: [String] = []

        lines.append("SiriKit Patterns Found:")
        let counts = result.countsByType
        for type in PatternType.allCases {
            lines.append("  - \(type.displayLabel): \(counts[type] ?? 0)")
        }
        lines.append("")
        lines.append("  Total patterns: \(result.totalCount)")
        lines.append("  Files affected: \(result.filesAffected)")
        lines.append("  Files scanned:  \(result.filesScanned)")

        if result.patterns.isEmpty {
            lines.append("")
            lines.append("No SiriKit patterns found in \(result.root).")
        } else {
            let typeWidth = PatternType.allCases.map(\.rawValue.count).max() ?? 0
            lines.append("")
            lines.append("Details:")
            for group in result.patternsByFile {
                lines.append("")
                lines.append("\(group.file) (\(group.patterns.count))")
                for pattern in group.patterns {
                    let number = String(pattern.line).leftPadded(to: 5)
                    let type = pattern.patternType.rawValue.rightPadded(to: typeWidth)
                    lines.append("  \(number)  \(type)  \(pattern.code)")
                }
            }
        }

        if !result.skippedFiles.isEmpty {
            lines.append("")
            lines.append("Skipped \(result.skippedFiles.count) unreadable file(s):")
            for skipped in result.skippedFiles {
                lines.append("  \(skipped.file) — \(skipped.reason)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Writes the full result as pretty-printed JSON, creating intermediate directories as needed.
    ///
    /// - Throws: `ReportError.cannotWriteReport` when the destination cannot be created or written.
    static func generateJSONReport(result: ScanResult, outputPath: String) throws {
        try writeJSON(result, to: outputPath)
    }

    /// Writes the migration suggestions as pretty-printed JSON.
    static func generateJSONReport(suggestions: [MigrationSuggestion], root: String, outputPath: String) throws {
        try writeJSON(SuggestionReport(root: root, suggestions: suggestions), to: outputPath)
    }

    /// Writes a patch run's result as pretty-printed JSON.
    static func generateJSONReport(patch: PatchResult, outputPath: String) throws {
        try writeJSON(patch, to: outputPath)
    }

    /// Emits findings in the compiler diagnostic format Xcode parses.
    ///
    /// `<absolute path>:<line>: warning: <message>` on stdout of a Run Script build phase
    /// becomes an inline warning on the offending line, so a SiriKit call is flagged where
    /// the developer is already looking rather than in a separate report.
    ///
    /// Paths must be absolute for Xcode to resolve them back to a file.
    static func formatXcodeDiagnostics(result: ScanResult, severity: Severity = .warning) -> String {
        result.patterns.map { pattern in
            let path = absolutePath(of: pattern.file, root: result.root)
            let migration = CommonPatterns.byRule[pattern.rule]
            let advice = migration.map { " → \($0.title) [\($0.complexity.displayLabel)]" } ?? ""
            return "\(path):\(pattern.line): \(severity.rawValue): SiriKit: \(pattern.rule.rawValue)\(advice)"
        }
        .joined(separator: "\n")
    }

    enum Severity: String, Sendable {
        case warning
        /// Fails the build. For teams that want the migration enforced rather than advised.
        case error
    }

    private static func absolutePath(of file: String, root: String) -> String {
        file.hasPrefix("/") ? file : (root as NSString).appendingPathComponent(file)
    }

    /// Writes an already-formatted text report (the console migration guide) to disk.
    static func writeText(_ contents: String, outputPath: String) throws {
        let url = fileURL(for: outputPath)
        do {
            try createParentDirectory(of: url)
            try Data(contents.utf8).write(to: url, options: .atomic)
        } catch {
            throw ReportError.cannotWriteReport(path: url.path, underlying: error)
        }
    }

    private static func writeJSON<Payload: Encodable>(_ payload: Payload, to outputPath: String) throws {
        let url = fileURL(for: outputPath)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(payload)

            try createParentDirectory(of: url)
            try data.write(to: url, options: .atomic)
        } catch {
            throw ReportError.cannotWriteReport(path: url.path, underlying: error)
        }
    }

    private static func fileURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func createParentDirectory(of url: URL) throws {
        let directory = url.deletingLastPathComponent()
        guard !directory.path.isEmpty, !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }

    func rightPadded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
