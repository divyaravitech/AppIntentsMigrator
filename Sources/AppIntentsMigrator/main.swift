import ArgumentParser
import Foundation

struct AppIntentsMigrator: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-intents-migrator",
        abstract: "Migration tooling for moving legacy SiriKit code to App Intents.",
        version: "0.1.0",
        subcommands: [Scan.self, Suggest.self]
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

    func run() throws {
        let result = try SiriKitScanner().scan(path: path)
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

    func run() throws {
        let result = try SiriKitScanner().scan(path: path)
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

AppIntentsMigrator.main()
