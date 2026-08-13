import Foundation

/// The kind of legacy SiriKit construct a `DetectedPattern` refers to.
///
/// Raw values are the names used in the JSON report.
enum PatternType: String, Codable, CaseIterable, Sendable {
    /// A declaration or reference involving `INExtension`, the SiriKit extension entry point.
    case inExtension = "INExtension"
    /// An `INIntent` subclass, an `IN…IntentHandling` conformance, or an intent type reference.
    case inIntent = "INIntent"
    /// A legacy delegate/handler entry point (`handler(for:)`, `handle(intent:)`,
    /// `application(_:didFinishLaunchingWithOptions:)`, …).
    case delegateMethod = "DelegateMethod"
    /// Any other Intents / IntentsUI framework usage.
    case otherSiriKit = "OtherSiriKit"

    /// Label used in the console summary.
    var displayLabel: String {
        switch self {
        case .inExtension: return "INExtension subclasses"
        case .inIntent: return "INIntent subclasses"
        case .delegateMethod: return "Delegate methods"
        case .otherSiriKit: return "Other SiriKit patterns"
        }
    }
}

/// Identifies the specific detection rule that produced a finding.
///
/// Shared between `PatternDetector` (which owns the regexes) and `CommonPatterns`
/// (which owns the migration advice), so every rule is guaranteed to have a
/// migration mapped to it. Raw values are the human-readable rule names.
enum RuleID: String, Codable, CaseIterable, Sendable {
    // INExtension
    case inExtensionSubclass = "INExtension subclass"
    case inExtensionReference = "INExtension reference"

    // Legacy delegate / handler entry points
    case handlerForIntent = "INExtension handler(for:)"
    case handleIntent = "SiriKit handle(intent:)"
    case confirmIntent = "SiriKit confirm(intent:)"
    case resolveMethod = "SiriKit resolve method"
    case applicationHandlerFor = "UIApplication intent handler"
    case appLaunchDelegate = "App launch delegate"
    case userActivityContinuation = "NSUserActivity continuation"

    // Intents
    case customIntentSubclass = "Custom intent subclass"
    case intentHandlingProtocol = "Intent handling protocol"
    case resolutionResult = "Resolution result type"
    case intentTypeReference = "Intent type reference"

    // Everything else from Intents / IntentsUI
    case intentsImport = "Intents framework import"
    case interactionDonation = "INInteraction donation"
    case voiceShortcutAPI = "Voice shortcut API"
    case siriAuthorization = "Siri authorization API"
    case invocationPhrase = "Shortcut phrase configuration"
    case predictionEligibility = "Prediction eligibility"
    case infoPlistIntents = "Info.plist intent declaration"
    case trackingAuthorization = "Tracking authorization API"
    case intentsFrameworkType = "Intents framework type"
}

/// A single SiriKit pattern found at a specific line of a specific file.
struct DetectedPattern: Codable, Equatable, Sendable {
    /// The category this finding falls into.
    let patternType: PatternType
    /// Path of the file, relative to the scan root when the scan root is a directory.
    let file: String
    /// 1-based line number.
    let line: Int
    /// The source line, whitespace-trimmed.
    let code: String
    /// The exact substring that triggered the match.
    let match: String
    /// The rule that produced this finding.
    let rule: RuleID
}

/// A file the scanner could not read, and why.
struct SkippedFile: Codable, Equatable, Sendable {
    let file: String
    let reason: String
}

/// The outcome of scanning a file or directory tree.
struct ScanResult: Codable, Equatable, Sendable {
    /// The path that was scanned, as resolved by the scanner.
    let root: String
    /// Every pattern found, ordered by file and then by line.
    let patterns: [DetectedPattern]
    /// Total number of patterns found.
    let totalCount: Int
    /// Number of distinct files containing at least one pattern.
    let filesAffected: Int
    /// Number of Swift files successfully read during the scan.
    let filesScanned: Int
    /// Files that were found but could not be read (permissions, I/O errors).
    let skippedFiles: [SkippedFile]

    init(root: String, patterns: [DetectedPattern], filesScanned: Int, skippedFiles: [SkippedFile] = []) {
        self.root = root
        self.patterns = patterns
        self.totalCount = patterns.count
        self.filesAffected = Set(patterns.map(\.file)).count
        self.filesScanned = filesScanned
        self.skippedFiles = skippedFiles
    }

    /// Counts per pattern type, including types with no findings.
    var countsByType: [PatternType: Int] {
        var counts = Dictionary(uniqueKeysWithValues: PatternType.allCases.map { ($0, 0) })
        for pattern in patterns {
            counts[pattern.patternType, default: 0] += 1
        }
        return counts
    }

    /// Findings grouped by file, ordered by file path.
    var patternsByFile: [(file: String, patterns: [DetectedPattern])] {
        Dictionary(grouping: patterns, by: \.file)
            .sorted { $0.key < $1.key }
            .map { (file: $0.key, patterns: $0.value.sorted { $0.line < $1.line }) }
    }
}

// MARK: - Patching

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
    /// True when every patched file passed syntax validation. False means the
    /// changes were rolled back (or, in a dry run, that nothing was written).
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
