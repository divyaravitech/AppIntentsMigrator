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
