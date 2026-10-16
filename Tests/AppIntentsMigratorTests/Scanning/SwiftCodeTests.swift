import Testing
@testable import app_intents_migrator

@Suite("Parser-backed lexing")
struct SwiftCodeTests {

    @Test("Literal and comment forms a hand-written lexer got wrong")
    func awkwardLiterals() {
        let source = [
            ###"let a = #"raw \(not interpolation) INExtension"#"###,
            ###"let c = ##"deeper raw "# INIntent"##"###,
            "/* block /* nested */ class Hidden: INExtension {} */",
            #"let d = "trailing // not a comment INPreferences""#,
            "let e = /INExtension[0-9]+/",
            "let real: INExtension? = nil",
        ].joined(separator: "\n")

        let found = PatternDetector().detect(in: source, file: "F.swift")
        #expect(found.map(\.line) == [6])
        #expect(found.map(\.rule) == [.inExtensionReference])
    }

    @Test("Blanking keeps line and column positions")
    func positionsPreserved() {
        let source = "// comment\nlet s = \"string\"\nclass H: INExtension {}\n"
        let stripped = SwiftCode.strippingCommentsAndLiterals(from: source)
        let original = SourceLines.split(source)
        let blanked = SourceLines.split(stripped)

        #expect(original.count == blanked.count)
        for (a, b) in zip(original, blanked) {
            #expect(a.text.count == b.text.count, "column positions must not shift")
        }
        #expect(blanked[2].text.contains("INExtension"))
        #expect(!blanked[1].text.contains("string"))
    }
}
