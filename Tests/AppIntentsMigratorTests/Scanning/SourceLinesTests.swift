import Testing
@testable import app_intents_migrator

@Suite("Line endings and interpolation")
struct SourceShapeTests {

    /// Swift treats "\r\n" as one Character, so splitting on "\n" silently collapsed a
    /// CRLF file into a single line — losing most findings and every line number.
    @Test("CRLF files find the same patterns as LF files")
    func crlfMatchesLF() {
        let body = [
            "import Intents",
            "class H: INExtension {}",
            "let i = INSendMessageIntent()",
            "INPreferences.requestSiriAuthorization { _ in }",
        ]
        let lf = rulesFired(in: body.joined(separator: "\n"))
        let crlf = rulesFired(in: body.joined(separator: "\r\n"))
        let cr = rulesFired(in: body.joined(separator: "\r"))

        #expect(lf.count == 4)
        #expect(crlf == lf)
        #expect(cr == lf)
    }

    @Test("Line numbers are correct in a CRLF file")
    func crlfLineNumbers() {
        let source = ["import Intents", "struct A {}", "class H: INExtension {}"].joined(separator: "\r\n")
        let found = PatternDetector().detect(in: source, file: "F.swift")
        #expect(found.map(\.line) == [1, 3])
    }

    /// `"\(dict["key"])"` used to end the string at the inner quote, exposing the rest of
    /// the literal as code.
    @Test("String interpolation containing quotes stays a string")
    func interpolationIsNotCode() {
        #expect(rulesFired(in: "let c = \"text: \\(name[\"INExtension\"])\"").isEmpty)
        #expect(rulesFired(in: "let b = \"\\(items.map { \"\\($0)\" }) INPreferences\"").isEmpty)
        // Real code after such a string must still be found.
        #expect(rulesFired(in: "let c = \"\\(a[\"k\"])\"; let r: INExtension? = nil") == [.inExtensionReference])
    }

    @Test("Splitting preserves each line's terminator")
    func terminatorsPreserved() {
        let source = "a\r\nb\nc\rd"
        let lines = SourceLines.split(source)
        #expect(lines.map(\.text) == ["a", "b", "c", "d"])
        #expect(lines.map(\.terminator) == ["\r\n", "\n", "\r", ""])
        #expect(SourceLines.join(lines) == source)
    }
}
