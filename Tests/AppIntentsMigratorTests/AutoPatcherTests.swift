import Foundation
import Testing
@testable import AppIntentsMigrator

@Suite("Auto-patcher")
struct AutoPatcherTests {

    /// Runs the patcher over a throwaway project and returns the result plus the file contents.
    private func patch(
        _ files: [String: String],
        mode: AutoPatcher.Mode = .dryRun,
        allowProposals: Bool = false
    ) async throws -> (result: PatchResult, contents: [String: String]) {
        try await withProject(files) { root in
            let (scan, found) = try suggestions(for: root)
            let patcher = AutoPatcher(mode: mode, allowProposals: allowProposals)
            let result = try await patcher.patchProject(root: scan.root, suggestions: found)

            var contents: [String: String] = [:]
            for name in files.keys {
                contents[name] = try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            }
            return (result, contents)
        }
    }

    @Test("A dry run writes nothing")
    func dryRunWritesNothing() async throws {
        let source = "import Intents\n"
        let (result, contents) = try await patch(["A.swift": source])

        #expect(result.edits.count == 1)
        #expect(contents["A.swift"] == source)
    }

    // MARK: The import swap

    @Test("Swaps the import when no SiriKit remains")
    func swapsImportWhenSafe() async throws {
        let (_, contents) = try await patch(["A.swift": "import Intents\nstruct A {}\n"], mode: .apply)
        #expect(contents["A.swift"]?.contains("import AppIntents") == true)
        #expect(contents["A.swift"]?.contains("import Intents\n") == false)
    }

    @Test("Defers the import swap while SiriKit symbols remain")
    func defersImportSwapWhenUsageRemains() async throws {
        // Swapping here would leave INSendMessageIntent unresolved, and an unresolved
        // symbol still parses — so the validator could not catch it.
        let (result, contents) = try await patch(["A.swift": "import Intents\nlet i = INSendMessageIntent()\n"])

        #expect(contents["A.swift"]?.contains("import Intents") == true)
        #expect(!result.edits.contains { $0.rule == .intentsImport })
        #expect(result.skipped.contains { $0.contains("import swap deferred") })
    }

    @Test("Swaps the import when the only remaining usage is itself deleted")
    func swapsImportAfterDeletionClearsUsage() async throws {
        let source = "import Intents\nfunc f() {\n    INPreferences.requestSiriAuthorization { _ in }\n}\n"
        let (_, contents) = try await patch(["A.swift": source], mode: .apply)

        #expect(contents["A.swift"]?.contains("import AppIntents") == true)
        #expect(contents["A.swift"]?.contains("INPreferences") == false)
    }

    @Test("Collapses Intents and IntentsUI into one import")
    func dedupesImports() async throws {
        let (_, contents) = try await patch(["A.swift": "import Intents\nimport IntentsUI\n"], mode: .apply)
        let occurrences = contents["A.swift"]?.components(separatedBy: "import AppIntents").count ?? 0
        #expect(occurrences == 2, "expected exactly one import AppIntents")
    }

    // MARK: Deletion guards

    @Test("Never deletes the opening line of a multi-line call")
    func skipsMultiLineAuthorizationCall() async throws {
        let source = "import Intents\nfunc f() {\n    INPreferences.requestSiriAuthorization { status in\n        print(status)\n    }\n}\n"
        let (_, contents) = try await patch(["A.swift": source], mode: .apply)
        #expect(contents["A.swift"]?.contains("requestSiriAuthorization { status in") == true)
    }

    @Test("Never deletes a prediction flag read in an expression")
    func skipsPredictionReadInExpression() async throws {
        let source = "import Intents\nlet flag = activity.isEligibleForPrediction\n"
        let (_, contents) = try await patch(["A.swift": source], mode: .apply)
        #expect(contents["A.swift"]?.contains("let flag = activity.isEligibleForPrediction") == true)
    }

    // MARK: Scope guards

    @Test("Refuses to patch anything that is not Swift")
    func refusesNonSwiftFiles() async throws {
        let plist = "<key>IntentsSupported</key>\n<string>INSendMessageIntent</string>\n"
        let (result, contents) = try await patch(["Info.plist": plist], mode: .apply)

        #expect(result.filesPatched == 0)
        #expect(contents["Info.plist"] == plist)
        #expect(result.skipped.contains { $0.contains("not a Swift file") })
    }

    @Test("Leaves structural rewrites alone by default")
    func structuralRewritesAreOptIn() async throws {
        let source = "import Intents\nclass IntentHandler: INExtension {\n}\n"
        let (result, _) = try await patch(["A.swift": source])

        #expect(!result.edits.contains { $0.safety == .proposalOnly })
        #expect(result.skipped.contains { $0.contains("needs a human") })
    }

    @Test("Applies structural rewrites when explicitly opted into")
    func structuralRewritesApplyWhenRequested() async throws {
        let source = "import Intents\nclass IntentHandler: INExtension {\n}\n"
        let (result, _) = try await patch(["A.swift": source], allowProposals: true)

        #expect(result.edits.contains { $0.patchRuleID == "inextension-class-to-struct" })
    }
}

@Suite("Backups")
struct BackupManagerTests {

    @Test("Restoring a backup reproduces the original bytes")
    func roundTripIsExact() async throws {
        let original = "import Intents\nlet i = INSendMessageIntent()\n"
        try await withProject(["A.swift": original, "Nested/B.swift": "import Intents\n"]) { root in
            let manager = BackupManager()
            let backup = try await manager.createBackup(projectPath: root.path)
            #expect(backup.fileCount == 2)

            let fileA = root.appendingPathComponent("A.swift")
            try "corrupted".write(to: fileA, atomically: true, encoding: .utf8)

            try await manager.restoreBackup(backup)
            let restored = try String(contentsOf: fileA, encoding: .utf8)
            #expect(restored == original)
        }
    }

    @Test("Archive name matches the documented format")
    func archiveNameIsDocumented() async throws {
        try await withProject(["A.swift": "let a = 1\n"]) { root in
            let backup = try await BackupManager().createBackup(projectPath: root.path)
            let name = (backup.path as NSString).lastPathComponent
            #expect(name.hasPrefix("AppIntentsMigrator.backup-"))
            #expect(name.hasSuffix(".tar.gz"))
        }
    }

    @Test("A missing archive is reported, not ignored")
    func missingArchiveThrows() async throws {
        await #expect(throws: PatchError.self) {
            _ = try await AutoPatcher(mode: .apply).rollback(archivePath: "/nonexistent/backup.tar.gz")
        }
    }
}

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
