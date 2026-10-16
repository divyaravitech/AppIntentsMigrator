import Foundation

/// Splits on CRLF, LF and CR, keeping each terminator.
/// Swift treats "\r\n" as one Character, so splitting on "\n" alone misses it.
enum SourceLines {

    struct Line: Equatable {
        /// The line's content, without its terminator.
        var text: String
        /// `"\r\n"`, `"\n"`, `"\r"`, or `""` for a final line with no trailing newline.
        let terminator: String
    }

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
