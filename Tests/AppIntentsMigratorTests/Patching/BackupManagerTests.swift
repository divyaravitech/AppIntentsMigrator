import Foundation
import Testing
@testable import app_intents_migrator

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
