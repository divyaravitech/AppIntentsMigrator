import Foundation
import SwiftParser
import SwiftSyntax

/// Blanks out comments and string literals using the real Swift parser.
///
/// Replaces a hand-written lexer that repeatedly got this wrong: nested block comments,
/// raw strings, multi-line strings, and interpolation containing its own string literals.
enum SwiftCode {

    /// Returns `source` with comment and string-literal bytes replaced by spaces.
    ///
    /// Line and column positions are unchanged, so findings still map onto the original
    /// text. Newlines inside a blanked range are kept, otherwise a multi-line string would
    /// collapse the lines around it.
    static func strippingCommentsAndLiterals(from source: String) -> String {
        let tree = Parser.parse(source: source)
        let collector = BlankRangeCollector(viewMode: .sourceAccurate)
        collector.walk(tree)

        var bytes = Array(source.utf8)
        for range in collector.ranges {
            for index in range where index < bytes.count {
                let byte = bytes[index]
                if byte != UInt8(ascii: "\n"), byte != UInt8(ascii: "\r") {
                    bytes[index] = UInt8(ascii: " ")
                }
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private final class BlankRangeCollector: SyntaxVisitor {
    private(set) var ranges: [Range<Int>] = []

    /// Whole literal, quotes included. Interpolation goes with it: a value spliced into a
    /// string is not a SiriKit call site.
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        ranges.append(node.position.utf8Offset..<node.endPosition.utf8Offset)
        return .skipChildren
    }

    override func visit(_ node: RegexLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        ranges.append(node.position.utf8Offset..<node.endPosition.utf8Offset)
        return .skipChildren
    }

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        collectComments(in: token.leadingTrivia, from: token.position.utf8Offset)
        collectComments(in: token.trailingTrivia, from: token.endPositionBeforeTrailingTrivia.utf8Offset)
        return .skipChildren
    }

    private func collectComments(in trivia: Trivia, from start: Int) {
        var offset = start
        for piece in trivia {
            let length = piece.sourceLength.utf8Length
            switch piece {
            case .lineComment, .blockComment, .docLineComment, .docBlockComment:
                ranges.append(offset..<(offset + length))
            default:
                break
            }
            offset += length
        }
    }
}
