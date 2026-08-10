import Foundation

/// How much work a migration needs.
enum Complexity: String, Codable, CaseIterable, Sendable {
    /// A mechanical, single-site edit that a tool could apply safely — an import swap,
    /// or deleting a call that has no replacement.
    case autoPatchable = "AutoPatchable"
    /// A structural change that depends on the surrounding code: new types, new
    /// parameter modelling, or behaviour that must be re-expressed.
    case manualReview = "ManualReview"

    var displayLabel: String {
        switch self {
        case .autoPatchable: return "Auto-patchable"
        case .manualReview: return "Manual review"
        }
    }
}

/// One SiriKit → App Intents migration recipe.
///
/// Owned by `CommonPatterns`, which is the single source of truth for all advice.
struct MigrationPattern: Codable, Equatable, Sendable {
    /// Stable identifier, used to group suggestions in reports.
    let id: String
    /// Short "X → Y" headline.
    let title: String
    /// The scanner category this recipe applies to.
    let patternType: PatternType
    /// Legacy SiriKit code.
    let beforeCode: String
    /// The App Intents equivalent.
    let afterCode: String
    /// Why the API changed and what to watch out for.
    let explanation: String
    let complexity: Complexity
    /// Verified developer.apple.com documentation URL.
    let appleDocLink: String
}

/// A migration recipe bound to one concrete finding in the scanned project.
struct MigrationSuggestion: Codable, Equatable, Sendable {
    /// The finding this suggestion addresses.
    let pattern: DetectedPattern
    /// Short "X → Y" headline, from the underlying `MigrationPattern`.
    let title: String
    let beforeCode: String
    let afterCode: String
    let explanation: String
    let complexity: Complexity
    let appleDocLink: String

    /// Identifier of the `MigrationPattern` this came from.
    let migrationID: String

    init(pattern: DetectedPattern, migration: MigrationPattern) {
        self.pattern = pattern
        self.title = migration.title
        self.beforeCode = migration.beforeCode
        self.afterCode = migration.afterCode
        self.explanation = migration.explanation
        self.complexity = migration.complexity
        self.appleDocLink = migration.appleDocLink
        self.migrationID = migration.id
    }

    /// `file:line` of the finding, for report headers.
    var location: String { "\(pattern.file):\(pattern.line)" }
}

/// Top-level payload for the JSON suggestion report.
struct SuggestionReport: Codable, Equatable, Sendable {
    let root: String
    let totalSuggestions: Int
    let autoPatchableCount: Int
    let manualReviewCount: Int
    let distinctMigrations: Int
    let suggestions: [MigrationSuggestion]

    init(root: String, suggestions: [MigrationSuggestion]) {
        self.root = root
        self.totalSuggestions = suggestions.count
        self.autoPatchableCount = suggestions.filter { $0.complexity == .autoPatchable }.count
        self.manualReviewCount = suggestions.filter { $0.complexity == .manualReview }.count
        self.distinctMigrations = Set(suggestions.map(\.migrationID)).count
        self.suggestions = suggestions
    }
}
