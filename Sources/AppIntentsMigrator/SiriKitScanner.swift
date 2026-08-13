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

    /// Shell-style globs matched against each path relative to the scan root, and against
    /// its last component. A matching file is skipped; a matching directory is not entered.
    var excludedGlobs: [String] = []

    var detector = PatternDetector()

    /// File extensions the scanner reads. Swift sources carry SiriKit calls; property lists
    /// carry the declarations (`IntentsSupported`, the intents extension point, and so on).
    private static let scannedExtensions: Set<String> = ["swift", "plist"]

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
        let files = scanningDirectory ? try scannableFiles(in: root) : [root]

        var patterns: [DetectedPattern] = []
        var skippedFiles: [SkippedFile] = []
        var filesScanned = 0

        for file in files {
            let relativePath = Self.path(of: file, relativeTo: scanningDirectory ? root : nil)
            do {
                let source = try Self.readSource(at: file)
                filesScanned += 1
                if file.pathExtension == "plist" {
                    patterns.append(contentsOf: detector.detectInPropertyList(in: source, file: relativePath))
                } else {
                    patterns.append(contentsOf: detector.detect(in: source, file: relativePath))
                }
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

    /// Every scannable file under `root`, excluding hidden directories, build output, and
    /// anything matching `excludedGlobs`.
    ///
    /// Directories that cannot be read are skipped rather than aborting the walk.
    private func scannableFiles(in root: URL) throws -> [URL] {
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
            // Resolved the same way as the root so relative paths can be derived by prefix.
            let resolved = url.resolvingSymlinksInPath()
            let relativePath = Self.path(of: resolved, relativeTo: root)

            if isDirectory {
                if excludedDirectories.contains(url.lastPathComponent) || isExcluded(relativePath) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard Self.scannedExtensions.contains(url.pathExtension), !isExcluded(relativePath) else { continue }
            files.append(resolved)
        }

        return files.sorted { $0.path < $1.path }
    }

    /// True when `relativePath` matches any exclusion glob, either in full or by basename,
    /// so both `Tests/*` and `*.generated.swift` behave the way callers expect.
    func isExcluded(_ relativePath: String) -> Bool {
        guard !excludedGlobs.isEmpty else { return false }
        let basename = (relativePath as NSString).lastPathComponent

        return excludedGlobs.contains { pattern in
            fnmatch(pattern, relativePath, 0) == 0 || fnmatch(pattern, basename, 0) == 0
        }
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
