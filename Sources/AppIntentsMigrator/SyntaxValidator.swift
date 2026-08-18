import Foundation

/// Checks patched files with the Swift compiler front end.
///
/// **What this can and cannot catch.** The default mode runs `swiftc -parse`, which is a
/// syntax-only check: it verifies the file still parses, and nothing more. It does *not*
/// catch type mismatches, missing members, or unresolved imports — a file where a class was
/// turned into a struct with `override` members still parses cleanly.
///
/// `-typecheck` catches those, but a single file compiled outside its module has no access
/// to the project's other types, and building for the host platform makes `import UIKit`
/// fail. On an iOS project it reports errors that are not real. It is therefore opt-in.
///
/// The practical consequence: passing validation means "still parses", which is enough to
/// catch a botched text substitution, and is not a promise that the project builds.
actor SyntaxValidator {

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
    ///
    /// Files are checked concurrently; each `swiftc` invocation is independent.
    func validateProject(_ path: String) async throws -> [ValidationError] {
        let files = try Self.swiftFiles(in: path)
        return try await validateFiles(files)
    }

    /// Validates a specific set of files concurrently.
    func validateFiles(_ paths: [String]) async throws -> [ValidationError] {
        guard !paths.isEmpty else { return [] }
        let mode = self.mode

        let results = try await withThrowingTaskGroup(of: ValidationResult.self) { group in
            for path in paths {
                group.addTask { try Self.validate(path: path, mode: mode) }
            }
            var collected: [ValidationResult] = []
            for try await result in group { collected.append(result) }
            return collected
        }

        return results
            .sorted { $0.file < $1.file }
            .flatMap(\.errors)
    }

    // MARK: - Compiler invocation

    private nonisolated static func validate(path: String, mode: Mode) throws -> ValidationResult {
        let outcome: Subprocess.Outcome
        do {
            outcome = try Subprocess.run("/usr/bin/xcrun", ["swiftc", "-\(mode.rawValue)", path])
        } catch let failure as Subprocess.Failure {
            // A compiler we cannot launch is a tooling problem, not invalid code. Reporting
            // it as a backup failure (as the shared helper used to) actively misled.
            throw PatchError.toolchainUnavailable(failure.errorDescription ?? "\(failure)")
        }

        // xcrun exiting non-zero without diagnostics means the toolchain is unusable.
        if outcome.status != 0, outcome.output.contains("unable to find utility") {
            throw PatchError.toolchainUnavailable(outcome.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return ValidationResult(file: path, errors: parseDiagnostics(outcome.output, file: path))
    }

    /// Extracts `path:line:column: error: message` diagnostics from compiler output.
    static func parseDiagnostics(_ output: String, file: String) -> [ValidationError] {
        var errors: [ValidationError] = []

        for line in output.split(separator: "\n") {
            let text = String(line)
            guard let errorRange = text.range(of: ": error: ") else { continue }

            let location = text[text.startIndex..<errorRange.lowerBound]
            let message = String(text[errorRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            // location is "<path>:<line>:<column>"
            let parts = location.split(separator: ":")
            let lineNumber = parts.count >= 3 ? Int(parts[parts.count - 2]) ?? 0 : 0

            errors.append(ValidationError(file: file, line: lineNumber, error: message))
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
