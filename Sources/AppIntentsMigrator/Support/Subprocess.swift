import Foundation

/// Runs an external command and captures its output.
enum Subprocess {

    struct Outcome: Sendable {
        let status: Int32
        /// Merged stdout and stderr.
        let output: String

        var succeeded: Bool { status == 0 }
    }

    enum Failure: LocalizedError, Equatable {
        case launchFailed(command: String, reason: String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let command, let reason):
                return "Could not run \(command): \(reason)"
            }
        }
    }

    /// Runs `launchPath` with `arguments`, returning its exit status and combined output.
    static func run(_ launchPath: String, _ arguments: [String]) throws -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw Failure.launchFailed(
                command: launchPath,
                reason: (error as NSError).localizedDescription
            )
        }

        // Drain before waiting: a full pipe buffer would otherwise deadlock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Outcome(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
