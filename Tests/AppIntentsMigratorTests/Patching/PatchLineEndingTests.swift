import Foundation
import Testing
@testable import app_intents_migrator

@Suite("Line endings on patch")
struct PatchLineEndingTests {

    /// Editing one line of a CRLF file must not rewrite the others to LF, which would turn
    /// a one-line change into a whole-file diff.
    @Test("A CRLF file keeps CRLF after patching")
    func crlfPreserved() async throws {
        let source = "import Intents\r\nstruct KeepMe {\r\n    let v = 42\r\n}\r\n"

        try await withProject(["A.swift": source]) { root in
            let (scan, found) = try suggestions(for: root)
            _ = try await AutoPatcher(mode: .apply).patchProject(root: scan.root, suggestions: found)

            let data = try Data(contentsOf: root.appendingPathComponent("A.swift"))
            let crlf = data.ranges(of: Data("\r\n".utf8)).count
            let allLF = data.ranges(of: Data("\n".utf8)).count

            #expect(crlf == 4, "every line should still end CRLF")
            #expect(crlf == allLF, "no line should have been converted to bare LF")

            let text = String(decoding: data, as: UTF8.self)
            #expect(text.contains("import AppIntents"))
            #expect(text.contains("KeepMe"))
        }
    }
}
