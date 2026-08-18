import Foundation
import PackagePlugin

/// Runs the migrator over the host package: `swift package app-intents-scan`.
///
/// Read-only by design — it declares no write permission, so it can never modify the
/// package it is inspecting. Patching stays in the CLI, where the backup and validation
/// gates apply and where the user has to ask for it explicitly.
@main
struct AppIntentsScanPlugin: CommandPlugin {

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "app-intents-migrator")

        // Default to `scan` on the package root; anything the caller passes wins, so
        // `swift package app-intents-scan -- suggest --summary` works too.
        let forwarded = arguments.isEmpty
            ? ["scan", context.package.directory.string, "--no-json"]
            : arguments

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.path.string)
        process.arguments = forwarded
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            Diagnostics.error("app-intents-migrator exited with status \(process.terminationStatus)")
        }
    }
}
