import ArgumentParser
import Foundation

struct AppIntentsMigrator: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-intents-migrator",
        abstract: "Migration tooling for moving legacy SiriKit code to App Intents.",
        version: "0.1.0",
        subcommands: [Scan.self]
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

AppIntentsMigrator.main()
