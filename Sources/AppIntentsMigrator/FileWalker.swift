import Foundation

/// Finds the files the tool operates on.
///
/// The single source of truth for which paths are in scope. The scanner, the validator and
/// the backup manager all walk the same tree and must agree on what counts — when the list
/// of ignored directories lived in each of them separately, they could silently drift, and a
/// backup could omit a file the scanner had just reported.
struct FileWalker: Sendable {

    enum WalkError: LocalizedError, Equatable {
        case notEnumerable(String)

        var errorDescription: String? {
            switch self {
            case .notEnumerable(let path):
                return "Could not enumerate directory: \(path)"
            }
        }
    }

    /// Build output and vendored dependencies, never scanned or patched.
    static let excludedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "DerivedData", "Pods", "Carthage", "node_modules",
    ]

    /// Extensions to collect. `["swift"]` for patching and validation; Swift plus `plist`
    /// for scanning, since SiriKit is declared in property lists as well as called in code.
    var extensions: Set<String>

    /// Shell-style globs matched against each path relative to the root, and against its
    /// last component, so both `Tests/*` and `*.generated.swift` behave as callers expect.
    var excludedGlobs: [String] = []

    init(extensions: Set<String>, excludedGlobs: [String] = []) {
        self.extensions = extensions
        self.excludedGlobs = excludedGlobs
    }

    /// Matching files under `root`, symlink-resolved and sorted.
    ///
    /// Unreadable directories are skipped rather than aborting the walk.
    func files(in root: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )
        else {
            throw WalkError.notEnumerable(root.path)
        }

        var found: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            // Resolved the same way as the root so relative paths can be derived by prefix.
            let resolved = url.resolvingSymlinksInPath()
            let relativePath = Self.relativePath(of: resolved, from: root)

            if isDirectory {
                if Self.excludedDirectories.contains(url.lastPathComponent) || isExcluded(relativePath) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard extensions.contains(url.pathExtension), !isExcluded(relativePath) else { continue }
            found.append(resolved)
        }

        return found.sorted { $0.path < $1.path }
    }

    /// True when `relativePath` matches any exclusion glob, by full path or by file name.
    func isExcluded(_ relativePath: String) -> Bool {
        guard !excludedGlobs.isEmpty else { return false }
        let basename = (relativePath as NSString).lastPathComponent

        return excludedGlobs.contains { pattern in
            fnmatch(pattern, relativePath, 0) == 0 || fnmatch(pattern, basename, 0) == 0
        }
    }

    /// `file` expressed relative to `root`, or its absolute path when it sits outside.
    static func relativePath(of file: URL, from root: URL?) -> String {
        guard let root else { return file.path }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(rootPath) else { return file.path }
        return String(file.path.dropFirst(rootPath.count))
    }

    /// Standardises a user-supplied path the way every entry point should.
    ///
    /// Symlinks are resolved because `FileManager`'s enumerator resolves them, and the two
    /// must agree or relative paths cannot be derived by prefix.
    static func normalize(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }
}
