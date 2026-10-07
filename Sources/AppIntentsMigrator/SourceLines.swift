import Foundation

/// Splits source into lines while remembering how each one ended.
///
/// Swift treats `"\r\n"` as a *single* `Character`, so `split(separator: "\n")` never
/// matches it and a CRLF file collapses into one enormous line. That silently cost three
/// quarters of the findings in a Windows-authored file, and made every reported line number
/// wrong, with no error to notice.
///
/// Terminators are preserved rather than normalised so the patcher can rewrite one line
/// without converting the rest of the file's line endings — an edit should not show up as a
/// whole-file whitespace change in review.
enum SourceLines {

    struct Line: Equatable {
        /// The line's content, without its terminator.
        var text: String
        /// `"\r\n"`, `"\n"`, `"\r"`, or `""` for a final line with no trailing newline.
        let terminator: String
    }

    /// Splits on CRLF, LF and CR, keeping each line's own terminator.
    static func split(_ source: String) -> [Line] {
        var lines: [Line] = []
        var current = ""

        for character in source {
            // "\r\n" is one Character in Swift and must be tested before the single-scalar
            // cases, which it would otherwise never equal.
            if character == "\r\n" || character == "\n" || character == "\r" {
                lines.append(Line(text: current, terminator: String(character)))
                current = ""
            } else {
                current.append(character)
            }
        }

        lines.append(Line(text: current, terminator: ""))
        return lines
    }

    /// Reassembles lines, restoring each original terminator.
    static func join(_ lines: [Line]) -> String {
        lines.reduce(into: "") { result, line in
            result += line.text + line.terminator
        }
    }
}
