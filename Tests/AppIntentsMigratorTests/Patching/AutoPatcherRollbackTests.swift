import Foundation
import Testing
@testable import app_intents_migrator

/// A validator that passes each file on its own but rejects them as a set.
///
/// Models the case the second gate exists for: every file is individually well-formed, but
/// the patch broke something that only shows up when they are compiled together.
private struct CrossFileFailureValidator: SourceValidating {
    func validateFile(_ path: String) async throws -> ValidationResult {
        ValidationResult(file: path, errors: [])
    }

    func validateFiles(_ paths: [String]) async throws -> [ValidationError] {
        paths.map { ValidationError(file: $0, line: 1, error: "cannot find 'Foo' in scope") }
    }
}

@Suite("Automatic rollback")
struct AutoPatcherRollbackTests {

    @Test("A failure after writing restores the backup")
    func rollsBackOnPostWriteFailure() async throws {
        let original = "import Intents\nstruct A {}\n"

        try await withProject(["A.swift": original]) { root in
            let (scan, found) = try suggestions(for: root)
            let patcher = AutoPatcher(mode: .apply, validator: CrossFileFailureValidator())
            let result = try await patcher.patchProject(root: scan.root, suggestions: found)

            // The write happened, the set failed, the backup went back.
            #expect(result.validated == false)
            #expect(result.filesPatched == 0)
            #expect(!result.validationErrors.isEmpty)

            let onDisk = try String(contentsOf: root.appendingPathComponent("A.swift"), encoding: .utf8)
            #expect(onDisk == original, "the working tree must be exactly as it was")
        }
    }

    @Test("The backup is kept so the failure can be inspected")
    func backupSurvivesRollback() async throws {
        try await withProject(["A.swift": "import Intents\nstruct A {}\n"]) { root in
            let (scan, found) = try suggestions(for: root)
            let patcher = AutoPatcher(mode: .apply, validator: CrossFileFailureValidator())
            let result = try await patcher.patchProject(root: scan.root, suggestions: found)

            let archive = try #require(result.backup?.path)
            #expect(FileManager.default.fileExists(atPath: archive))
        }
    }
}
