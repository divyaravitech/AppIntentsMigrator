import Foundation

/// Checks that Swift source is still well-formed.
protocol SourceValidating: Sendable {
    /// Checks one file in isolation.
    func validateFile(_ path: String) async throws -> ValidationResult
    /// Checks files as a set. In `-typecheck` mode they are compiled together, so breakage
    /// that spans files surfaces here and not in `validateFile`.
    func validateFiles(_ paths: [String]) async throws -> [ValidationError]
}

/// `-parse` checks syntax only: it does not catch type errors or unresolved imports.
/// `-typecheck` does, but reports false errors for files needing the rest of the module.
actor SyntaxValidator: SourceValidating {

    enum Mode: String, Sendable {
        /// `swiftc -parse` — syntax only. Reliable on any file.
        case parse
        /// `swiftc -typecheck` — also resolves types and imports, with false positives on
        /// files that depend on the rest of the module or on a non-host SDK.
        case typecheck
    }

    let mode: Mode

    init(mode: Mode = .parse) {
        self.mode = mode
    }

    /// Validates one Swift file.
    func validateFile(_ path: String) async throws -> ValidationResult {
        try Self.validate(path: path, mode: mode)
    }

    /// Validates every Swift file under `path`, returning only the failures.
    /// Files are checked concurrently; each `swiftc` invocation is independent.
    func validateProject(_ path: String) async throws -> [ValidationError] {
        let files = try Self.swiftFiles(in: path)
        return try await validateFiles(files)
    }

    /// Validates files as a single compiler invocation.
    func validateFiles(_ paths: [String]) async throws -> [ValidationError] {
        guard !paths.isEmpty else { return [] }
        let outcome = try Self.runCompiler(on: paths, mode: mode)
        return Self.parseDiagnostics(outcome.output, defaultFile: paths[0])
    }

    // MARK: - Compiler invocation

    private nonisolated static func validate(path: String, mode: Mode) throws -> ValidationResult {
        let outcome = try runCompiler(on: [path], mode: mode)
        return ValidationResult(file: path, errors: parseDiagnostics(outcome.output, defaultFile: path))
    }

    /// Beyond this many bytes of paths, arguments go in a response file instead of argv.
    /// ARG_MAX is 1 MB on macOS; a large monorepo would otherwise fail with a bare
    /// "argument list too long" that says nothing about what to do.
    private static let inlineArgumentLimit = 128_000

    private nonisolated static func runCompiler(on paths: [String], mode: Mode) throws -> Subprocess.Outcome {
        let inlineSize = paths.reduce(0) { $0 + $1.utf8.count + 1 }
        var responseFile: URL?
        let arguments: [String]

        if inlineSize > inlineArgumentLimit {
            // One invocation is kept deliberately: under -typecheck the files are compiled
            // together, and splitting them would silently lose cross-file checking.
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("appintents-swiftc-\(UUID().uuidString).resp")
            let quoted = paths.map { "\"\($0)\"" }.joined(separator: "\n")
            try? Data("-\(mode.rawValue)\n\(quoted)\n".utf8).write(to: url, options: .atomic)
            responseFile = url
            arguments = ["swiftc", "@\(url.path)"]
        } else {
            arguments = ["swiftc", "-\(mode.rawValue)"] + paths
        }
        defer { if let responseFile { try? FileManager.default.removeItem(at: responseFile) } }

        let outcome: Subprocess.Outcome
        do {
            outcome = try Subprocess.run("/usr/bin/xcrun", arguments)
        } catch let failure as Subprocess.Failure {
            // A compiler we cannot launch is a tooling problem, not invalid code. Reporting
            // it as a backup failure (as the shared helper used to) actively misled.
            throw PatchError.toolchainUnavailable(failure.errorDescription ?? "\(failure)")
        }

        // xcrun exiting non-zero without diagnostics means the toolchain is unusable.
        if outcome.status != 0, outcome.output.contains("unable to find utility") {
            throw PatchError.toolchainUnavailable(outcome.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return outcome
    }

    /// Extracts `path:line:column: error: message` diagnostics from compiler output.
    static func parseDiagnostics(_ output: String, defaultFile: String) -> [ValidationError] {
        var errors: [ValidationError] = []

        for line in output.split(separator: "\n") {
            let text = String(line)
            guard let errorRange = text.range(of: ": error: ") else { continue }

            let location = text[text.startIndex..<errorRange.lowerBound]
            let message = String(text[errorRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            // location is "<path>:<line>:<column>"
            let parts = location.split(separator: ":")
            let lineNumber = parts.count >= 3 ? Int(parts[parts.count - 2]) ?? 0 : 0
            let path = parts.count >= 3 ? parts[0..<(parts.count - 2)].joined(separator: ":") : defaultFile

            errors.append(ValidationError(file: path, line: lineNumber, error: message))
        }

        return errors
    }

    /// Swift files under `path`, or the file itself when `path` is one.
    private nonisolated static func swiftFiles(in path: String) throws -> [String] {
        let root = FileWalker.normalize(path)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw SiriKitScanner.ScanError.pathNotFound(path)
        }
        guard isDirectory.boolValue else { return [root.path] }

        return try FileWalker(extensions: ["swift"]).files(in: root).map(\.path)
    }
}
