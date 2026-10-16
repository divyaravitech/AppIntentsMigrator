import Testing
@testable import app_intents_migrator

@Suite("Scanner")
struct SiriKitScannerTests {

    @Test("Scans Swift sources and property lists")
    func scansSwiftAndPropertyLists() throws {
        try withProject([
            "A.swift": "import Intents\n",
            "Info.plist": "<key>IntentsSupported</key>\n",
            "README.md": "import Intents\n",
        ]) { root in
            let result = try SiriKitScanner().scan(path: root.path)
            #expect(result.filesScanned == 2, "markdown should not be scanned")
            #expect(result.totalCount == 2)
        }
    }

    @Test("Exclusion globs match by path and by file name")
    func exclusionGlobs() throws {
        let files = ["Sources/A.swift": "import Intents\n", "Fixtures/B.swift": "import Intents\n"]

        try withProject(files) { root in
            let all = try SiriKitScanner().scan(path: root.path).filesScanned
            #expect(all == 2)

            var byPath = SiriKitScanner()
            byPath.excludedGlobs = ["Fixtures/*"]
            let pathExcluded = try byPath.scan(path: root.path).filesScanned
            #expect(pathExcluded == 1)

            var byName = SiriKitScanner()
            byName.excludedGlobs = ["B.swift"]
            let nameExcluded = try byName.scan(path: root.path).filesScanned
            #expect(nameExcluded == 1)
        }
    }

    @Test("A missing path is an error, not an empty result")
    func missingPathThrows() {
        #expect(throws: SiriKitScanner.ScanError.self) {
            _ = try SiriKitScanner().scan(path: "/nonexistent/project")
        }
    }
}
