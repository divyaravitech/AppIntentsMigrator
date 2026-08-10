import Foundation

/// Walks a directory tree (or a single file) and reports every SiriKit pattern found in Swift sources.
struct SiriKitScanner: Sendable {

    enum ScanError: LocalizedError {
        case pathNotFound(String)
        case permissionDenied(String)
        case notEnumerable(String)

        var errorDescription: String? {
            switch self {
            case .pathNotFound(let path):
                return "No such file or directory: \(path)"
            case .permissionDenied(let path):
                return "Permission denied: \(path)"
            case .notEnumerable(let path):
                return "Could not enumerate directory: \(path)"
            }
        }
    }

    /// Directory names skipped during the walk: build output and vendored dependencies.
    var excludedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "DerivedData", "Pods", "Carthage", "node_modules",
    ]

    var detector = PatternDetector()

    /// Scans `path`, which may be a directory tree or a single `.swift` file.
    ///
    /// - Throws: `ScanError` when the root path is missing, unreadable, or cannot be enumerated.
    ///   Individual files that fail to read are recorded in `ScanResult.skippedFiles` rather than
    ///   aborting the whole scan.
    func scan(path: String) throws -> ScanResult {
        // Symlinks are resolved so that the root shares a prefix with the URLs produced by
        // `FileManager`'s enumerator (which resolves them), keeping reported paths relative.
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw ScanError.pathNotFound(path)
        }
        guard FileManager.default.isReadableFile(atPath: root.path) else {
            throw ScanError.permissionDenied(root.path)
        }

        let scanningDirectory = isDirectory.boolValue
        let files = scanningDirectory ? try swiftFiles(in: root) : [root]

        var patterns: [DetectedPattern] = []
        var skippedFiles: [SkippedFile] = []
        var filesScanned = 0

        for file in files {
            let relativePath = Self.path(of: file, relativeTo: scanningDirectory ? root : nil)
            do {
                let source = try Self.readSource(at: file)
                filesScanned += 1
                patterns.append(contentsOf: detector.detect(in: source, file: relativePath))
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

    /// Every `.swift` file under `root`, excluding hidden and build directories.
    ///
    /// Directories that cannot be read are skipped rather than aborting the walk.
    private func swiftFiles(in root: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )
        else {
            throw ScanError.notEnumerable(root.path)
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if excludedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension == "swift" {
                // Resolved the same way as the root so relative paths can be derived by prefix.
                files.append(url.resolvingSymlinksInPath())
            }
        }

        return files.sorted { $0.path < $1.path }
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
        if let scanError = error as? ScanError {
            return scanError.errorDescription ?? "\(scanError)"
        }
        return (error as NSError).localizedDescription
    }

    private static func path(of file: URL, relativeTo root: URL?) -> String {
        guard let root else { return file.path }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(rootPath) else { return file.path }
        return String(file.path.dropFirst(rootPath.count))
    }
}
