import Foundation

/// Creates and restores `.tar.gz` snapshots of a project's Swift sources.
///
/// Only `.swift` files are archived — those are the only files the patcher can modify,
/// and archiving build output would make backups enormous. Restoring therefore overwrites
/// Swift files that were captured; it does not delete files created after the backup.
actor BackupManager {

    static let archivePrefix = "AppIntentsMigrator.backup-"

    private let fileManager = FileManager.default

    /// Archives every Swift file under `projectPath` into the project root.
    ///
    /// - Throws: `PatchError.backupFailed` if the archive cannot be written. Callers must
    ///   treat that as fatal and leave the project untouched.
    func createBackup(projectPath: String) throws -> BackupInfo {
        let root = FileWalker.normalize(projectPath)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PatchError.backupFailed("\(root.path) is not a directory")
        }

        let relativePaths = try swiftFiles(in: root)
        guard !relativePaths.isEmpty else {
            throw PatchError.backupFailed("no Swift files found under \(root.path)")
        }

        let timestamp = Date()
        let archiveURL = root.appendingPathComponent(Self.archiveName(for: timestamp, in: root))

        // tar reads the file list from disk rather than argv, so projects with thousands
        // of sources cannot blow the argument limit.
        let listURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appintents-backup-\(UUID().uuidString).txt")
        try? relativePaths.joined(separator: "\n").write(to: listURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: listURL) }

        let outcome = try Self.run(
            "/usr/bin/tar",
            ["-czf", archiveURL.path, "-C", root.path, "-T", listURL.path]
        )
        guard outcome.status == 0 else {
            throw PatchError.backupFailed(outcome.output.isEmpty ? "tar exited \(outcome.status)" : outcome.output)
        }

        return BackupInfo(path: archiveURL.path, timestamp: timestamp, fileCount: relativePaths.count)
    }

    /// Extracts a backup over the project it came from.
    func restoreBackup(_ backup: BackupInfo) throws {
        let archiveURL = URL(fileURLWithPath: backup.path)
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw PatchError.backupNotFound(backup.path)
        }

        let root = archiveURL.deletingLastPathComponent()
        let outcome = try Self.run("/usr/bin/tar", ["-xzf", archiveURL.path, "-C", root.path])
        guard outcome.status == 0 else {
            throw PatchError.rollbackFailed(outcome.output.isEmpty ? "tar exited \(outcome.status)" : outcome.output)
        }
    }

    /// Loads a backup by archive path, reading its real timestamp and file count.
    func backup(at path: String) throws -> BackupInfo {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PatchError.backupNotFound(url.path)
        }

        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let timestamp = (attributes?[.modificationDate] as? Date) ?? Date()

        let listing = try Self.run("/usr/bin/tar", ["-tzf", url.path])
        let count = listing.status == 0
            ? listing.output.split(separator: "\n").filter { $0.hasSuffix(".swift") }.count
            : 0

        return BackupInfo(path: url.path, timestamp: timestamp, fileCount: count)
    }

    /// Existing backup archives in a project root, newest first.
    func existingBackups(in projectPath: String) -> [String] {
        let root = URL(fileURLWithPath: (projectPath as NSString).expandingTildeInPath)
        let contents = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        return contents
            .filter { $0.hasPrefix(Self.archivePrefix) && $0.hasSuffix(".tar.gz") }
            .sorted(by: >)
            .map { root.appendingPathComponent($0).path }
    }

    // MARK: - Helpers

    /// `AppIntentsMigrator.backup-YYYY-MM-DD.tar.gz`, with a time suffix appended only when
    /// that name is already taken, so a second run on the same day cannot clobber the first.
    private static func archiveName(for date: Date, in root: URL) -> String {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = .current

        let base = "\(archivePrefix)\(day.string(from: date))"
        let plain = "\(base).tar.gz"
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(plain).path) else {
            return plain
        }

        let time = DateFormatter()
        time.dateFormat = "HHmmss"
        time.locale = Locale(identifier: "en_US_POSIX")
        time.timeZone = .current
        return "\(base)-\(time.string(from: date)).tar.gz"
    }

    /// Swift files under `root`, as paths relative to it.
    ///
    /// Scope comes from `FileWalker`, so a backup covers exactly the files the patcher
    /// could modify.
    private func swiftFiles(in root: URL) throws -> [String] {
        try FileWalker(extensions: ["swift"])
            .files(in: root)
            .map { FileWalker.relativePath(of: $0, from: root) }
    }

    /// Runs `tar`, reporting a launch failure as a backup problem.
    nonisolated static func run(_ launchPath: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        do {
            let outcome = try Subprocess.run(launchPath, arguments)
            return (outcome.status, outcome.output)
        } catch let failure as Subprocess.Failure {
            throw PatchError.backupFailed(failure.errorDescription ?? "\(failure)")
        }
    }
}
