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
        let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(result)

            let directory = url.deletingLastPathComponent()
            if !directory.path.isEmpty, !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try data.write(to: url, options: .atomic)
        } catch {
            throw ReportError.cannotWriteReport(path: url.path, underlying: error)
        }
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
