import Foundation

/// How much the patcher trusts a rewrite rule.
enum PatchSafety: String, Codable, CaseIterable, Sendable {
    /// Line-local and semantics-preserving. Applied by `--apply`.
    case automatic = "Automatic"
    /// A structural rewrite that cannot be verified by text substitution alone.
    /// Shown by `--dry-run`, but only written when explicitly opted into.
    case proposalOnly = "ProposalOnly"

    var displayLabel: String {
        switch self {
        case .automatic: return "auto"
        case .proposalOnly: return "proposal"
        }
    }
}

/// A single line-level change the patcher would make.
struct PatchEdit: Codable, Equatable, Sendable {
    /// Path relative to the scan root.
    let file: String
    /// 1-based line number in the original file.
    let line: Int
    let before: String
    /// Replacement text, or `nil` when the line is deleted.
    let after: String?
    /// Scanner rule that flagged the line.
    let rule: RuleID
    /// Identifier of the `PatchingRule` that produced the change.
    let patchRuleID: String
    let safety: PatchSafety

    var isDeletion: Bool { after == nil }
}

/// Outcome of a patch run.
struct PatchResult: Codable, Equatable, Sendable {
    let filesPatched: Int
    let linesChanged: Int
    /// Human-readable reasons for findings that were not patched.
    let skipped: [String]
    /// False means the changes were rolled back, or nothing was written.
    let validated: Bool
    /// Every change made or proposed, for reporting.
    let edits: [PatchEdit]
    /// Backup taken before writing, when the run wrote anything.
    let backup: BackupInfo?
    /// Validation failures that caused a rollback.
    let validationErrors: [ValidationError]

    init(
        filesPatched: Int,
        linesChanged: Int,
        skipped: [String],
        validated: Bool,
        edits: [PatchEdit] = [],
        backup: BackupInfo? = nil,
        validationErrors: [ValidationError] = []
    ) {
        self.filesPatched = filesPatched
        self.linesChanged = linesChanged
        self.skipped = skipped
        self.validated = validated
        self.edits = edits
        self.backup = backup
        self.validationErrors = validationErrors
    }
}

/// A snapshot archive of the Swift files in a project.
struct BackupInfo: Codable, Equatable, Sendable {
    /// Absolute path of the `.tar.gz` archive.
    let path: String
    let timestamp: Date
    let fileCount: Int
}

/// One diagnostic emitted by the Swift compiler.
struct ValidationError: Codable, Equatable, Sendable {
    let file: String
    let line: Int
    let error: String
}

/// Result of validating a single file.
struct ValidationResult: Codable, Equatable, Sendable {
    let file: String
    let errors: [ValidationError]

    var isValid: Bool { errors.isEmpty }
}

enum PatchError: LocalizedError, Equatable {
    case backupFailed(String)
    case compilationFailed(file: String)
    case rollbackFailed(String)
    case backupNotFound(String)
    case toolchainUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .backupFailed(let reason):
            return "Could not create a backup, so nothing was changed: \(reason)"
        case .compilationFailed(let file):
            return "Patched file failed validation: \(file)"
        case .rollbackFailed(let reason):
            return "Rollback failed — restore the backup archive manually: \(reason)"
        case .backupNotFound(let path):
            return "No backup archive at \(path)"
        case .toolchainUnavailable(let reason):
            return "Could not run the Swift compiler for validation: \(reason)"
        }
    }
}
