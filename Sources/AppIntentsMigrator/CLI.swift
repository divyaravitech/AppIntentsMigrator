import ArgumentParser
import Foundation

@main
struct AppIntentsMigrator: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-intents-migrator",
        abstract: "Migration tooling for moving legacy SiriKit code to App Intents.",
        version: "0.1.0",
        subcommands: [Scan.self, Suggest.self, Patch.self]
    )
}

struct Scan: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan a Swift project for SiriKit patterns."
    )

    @Argument(help: "Directory or .swift file to scan.")
    var path: String

    @Option(name: .customLong("json"), help: "Path for the JSON report.")
    var jsonOutputPath: String = "migration_report.json"

    @Flag(name: .customLong("no-json"), help: "Skip writing the JSON report.")
    var skipJSON: Bool = false

    @Option(
        name: .customLong("exclude"),
        help: ArgumentHelp(
            "Glob of paths to skip. Repeatable.",
            discussion: "Matched against each path relative to the scan root and against its file name, e.g. --exclude 'Tests/*' --exclude '*.generated.swift'."
        )
    )
    var excludedGlobs: [String] = []

    func run() throws {
        let result = try SiriKitScanner(excludedGlobs: excludedGlobs).scan(path: path)
        print(Reporter.formatConsoleReport(result: result))

        guard !skipJSON else { return }
        try Reporter.generateJSONReport(result: result, outputPath: jsonOutputPath)
        print("  Report saved: \(jsonOutputPath)")
    }
}

struct Suggest: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "suggest",
        abstract: "Scan a project and print App Intents migration suggestions."
    )

    @Argument(help: "Directory or .swift file to scan.")
    var path: String

    @Option(
        name: [.customLong("output"), .customShort("o")],
        help: "Save the report. A .json path writes JSON; any other extension writes the text guide."
    )
    var outputPath: String?

    @Flag(name: .customLong("summary"), help: "Print only the summary counts, without the guide.")
    var summaryOnly: Bool = false

    @Option(
        name: .customLong("exclude"),
        help: ArgumentHelp(
            "Glob of paths to skip. Repeatable.",
            discussion: "Matched against each path relative to the scan root and against its file name, e.g. --exclude 'Tests/*' --exclude '*.generated.swift'."
        )
    )
    var excludedGlobs: [String] = []

    func run() throws {
        let result = try SiriKitScanner(excludedGlobs: excludedGlobs).scan(path: path)
        let suggestions = SuggestionGenerator().generateSuggestions(patterns: result.patterns)
        let guide = MigrationGuideFormatter.formatSuggestions(suggestions: suggestions)

        if summaryOnly {
            // The header block, up to the first migration section.
            print(guide.components(separatedBy: "\n\n")[0])
        } else {
            print(guide)
        }

        guard let outputPath else { return }
        if (outputPath as NSString).pathExtension.lowercased() == "json" {
            try Reporter.generateJSONReport(suggestions: suggestions, root: result.root, outputPath: outputPath)
        } else {
            try Reporter.writeText(guide, outputPath: outputPath)
        }
        print("")
        print("  Report saved: \(outputPath)")
    }
}

struct Patch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "patch",
        abstract: "Apply the safe subset of App Intents migrations, with a backup and a validation gate.",
        discussion: """
        Only line-local, semantics-preserving rewrites are applied by default. Structural \
        changes (INExtension → AppIntent and friends) cannot be done safely by text \
        substitution and are reported instead; pass --include-structural to write them \
        anyway, at your own risk.

        Every run backs the project up first, and any change that fails validation is \
        discarded before it reaches your working tree.
        """
    )

    @Argument(help: "Project directory to patch.")
    var path: String

    @Flag(name: .customLong("dry-run"), help: "Show the changes without writing them.")
    var dryRun: Bool = false

    @Flag(name: .customLong("apply"), help: "Write the changes (the default).")
    var apply: Bool = false

    @Option(name: .customLong("rollback"), help: "Restore a backup archive, undoing a previous run.")
    var rollbackArchive: String?

    @Flag(name: .customLong("validate-only"), help: "Only check that the project's Swift files parse.")
    var validateOnly: Bool = false

    @Flag(
        name: .customLong("include-structural"),
        help: "Also write structural rewrites. These generally will not compile without follow-up edits."
    )
    var includeStructural: Bool = false

    @Flag(
        name: .customLong("typecheck"),
        help: "Validate with swiftc -typecheck instead of -parse. Stricter, but reports false errors for iOS-only files."
    )
    var typecheck: Bool = false

    @Option(name: [.customLong("output"), .customShort("o")], help: "Write the patch report as JSON.")
    var outputPath: String?

    @Option(
        name: .customLong("exclude"),
        help: ArgumentHelp(
            "Glob of paths to skip. Repeatable.",
            discussion: "Matched against each path relative to the scan root and against its file name, e.g. --exclude 'Tests/*' --exclude '*.generated.swift'."
        )
    )
    var excludedGlobs: [String] = []

    func run() async throws {
        let validationMode: SyntaxValidator.Mode = typecheck ? .typecheck : .parse

        if let rollbackArchive {
            try await runRollback(archive: rollbackArchive)
            return
        }
        if validateOnly {
            try await runValidateOnly(mode: validationMode)
            return
        }

        let mode: AutoPatcher.Mode = dryRun ? .dryRun : .apply
        let result = try SiriKitScanner(excludedGlobs: excludedGlobs).scan(path: path)
        let suggestions = SuggestionGenerator().generateSuggestions(patterns: result.patterns)

        let patcher = AutoPatcher(mode: mode, validation: validationMode, allowProposals: includeStructural)
        if mode == .apply, includeStructural {
            print("WARNING: --include-structural writes rewrites that usually need follow-up edits.")
            print("         Your backup is the way back. Review the diff before committing.\n")
        }

        let patchResult = try await patcher.patchProject(root: result.root, suggestions: suggestions)
        print(MigrationGuideFormatter.formatPatchResult(patchResult, mode: mode, validationMode: validationMode))

        if let outputPath {
            try Reporter.generateJSONReport(patch: patchResult, outputPath: outputPath)
            print("")
            print("  Report saved: \(outputPath)")
        }

        if !patchResult.validated {
            throw ExitCode(1)
        }
    }

    private func runRollback(archive: String) async throws {
        let patcher = AutoPatcher(mode: .apply)
        let backup = try await patcher.rollback(archivePath: archive)
        print("Restored \(backup.fileCount) file(s) from \((backup.path as NSString).lastPathComponent)")
        print("Backup taken: \(backup.timestamp.formatted(date: .abbreviated, time: .shortened))")
    }

    private func runValidateOnly(mode: SyntaxValidator.Mode) async throws {
        let validator = SyntaxValidator(mode: mode)
        let scan = try SiriKitScanner(excludedGlobs: excludedGlobs).scan(path: path)
        let errors = try await validator.validateProject(path)
        print(MigrationGuideFormatter.formatValidation(errors, fileCount: scan.filesScanned, mode: mode))
        if !errors.isEmpty { throw ExitCode(1) }
    }
}
