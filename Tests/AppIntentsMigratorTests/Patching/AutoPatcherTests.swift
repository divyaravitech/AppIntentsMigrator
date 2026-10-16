import Foundation
import Testing
@testable import app_intents_migrator

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
