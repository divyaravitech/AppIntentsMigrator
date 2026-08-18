import Foundation
@testable import app_intents_migrator

/// Creates a throwaway project directory from `files`, keyed by relative path.
///
/// The caller owns the directory and should remove it; `withProject` does that for you.
func makeProject(_ files: [String: String]) throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("aim-tests-\(UUID().uuidString)")

    for (relativePath, contents) in files {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    return root
}

func withProject<T>(_ files: [String: String], _ body: (URL) throws -> T) throws -> T {
    let root = try makeProject(files)
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(root)
}

func withProject<T>(_ files: [String: String], _ body: (URL) async throws -> T) async throws -> T {
    let root = try makeProject(files)
    defer { try? FileManager.default.removeItem(at: root) }
    return try await body(root)
}

/// Scans `root` and turns the findings into suggestions, the way the CLI does.
func suggestions(for root: URL) throws -> (ScanResult, [MigrationSuggestion]) {
    let result = try SiriKitScanner().scan(path: root.path)
    return (result, SuggestionGenerator().generateSuggestions(patterns: result.patterns))
}

/// Rules fired by scanning a single Swift source string.
func rulesFired(in source: String) -> [RuleID] {
    PatternDetector().detect(in: source, file: "Test.swift").map(\.rule)
}
