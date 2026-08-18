import Foundation

/// Walks a project (or a single file) and reports every SiriKit pattern found.
struct SiriKitScanner: Sendable {

    enum ScanError: LocalizedError, Equatable {
        case pathNotFound(String)
        case permissionDenied(String)

        var errorDescription: String? {
            switch self {
            case .pathNotFound(let path):
                return "No such file or directory: \(path)"
            case .permissionDenied(let path):
                return "Permission denied: \(path)"
            }
        }
    }

    /// Swift sources carry SiriKit calls; property lists carry the declarations.
    static let scannedExtensions: Set<String> = ["swift", "plist"]

    /// Globs of paths to skip. See `FileWalker.isExcluded`.
    var excludedGlobs: [String] = []

    var detector = PatternDetector()

    /// Scans `path`, which may be a directory tree or a single file.
    ///
    /// - Throws: `ScanError` when the root is missing or unreadable, or `FileWalker.WalkError`
    ///   when the tree cannot be enumerated. Individual files that fail to read are recorded
    ///   in `ScanResult.skippedFiles` rather than aborting the scan.
    func scan(path: String) throws -> ScanResult {
        let root = FileWalker.normalize(path)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw ScanError.pathNotFound(path)
        }
        guard FileManager.default.isReadableFile(atPath: root.path) else {
            throw ScanError.permissionDenied(root.path)
        }

        let scanningDirectory = isDirectory.boolValue
        let walker = FileWalker(extensions: Self.scannedExtensions, excludedGlobs: excludedGlobs)
        let files = scanningDirectory ? try walker.files(in: root) : [root]

        var patterns: [DetectedPattern] = []
        var skippedFiles: [SkippedFile] = []
        var filesScanned = 0

        for file in files {
            let relativePath = FileWalker.relativePath(of: file, from: scanningDirectory ? root : nil)
            do {
                let source = try Self.readSource(at: file)
                filesScanned += 1
                patterns.append(contentsOf: detect(in: source, file: relativePath, isPropertyList: file.pathExtension == "plist"))
            } catch {
                skippedFiles.append(SkippedFile(file: relativePath, reason: Self.describe(error)))
            }
        }

        return ScanResult(
            root: root.path,
            patterns: patterns,
            filesScanned: filesScanned,
            skippedFiles: skippedFiles
        )
    }

    private func detect(in source: String, file: String, isPropertyList: Bool) -> [DetectedPattern] {
        isPropertyList
            ? detector.detectInPropertyList(in: source, file: file)
            : detector.detect(in: source, file: file)
    }

    /// Reads a source file, falling back to Latin-1 so that a stray non-UTF-8 byte
    /// does not silently drop the file from the scan.
    private static func readSource(at url: URL) throws -> String {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ScanError.permissionDenied(url.path)
        }
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        return try String(contentsOf: url, encoding: .isoLatin1)
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
    }
}
