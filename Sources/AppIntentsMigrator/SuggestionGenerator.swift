import Foundation

/// Turns scanner findings into actionable migration suggestions.
///
/// All advice comes from `CommonPatterns`; this type only binds a recipe to a finding.
struct SuggestionGenerator: Sendable {

    /// One suggestion per finding, in the order the patterns were detected.
    ///
    /// Findings with no mapped migration are dropped rather than guessed at. Because
    /// `CommonPatterns` covers every `RuleID`, that case does not arise today — see
    /// `CommonPatterns.unmappedRules`.
    func generateSuggestions(patterns: [DetectedPattern]) -> [MigrationSuggestion] {
        patterns.compactMap { pattern in
            guard let migration = CommonPatterns.migration(for: pattern) else { return nil }
            return MigrationSuggestion(pattern: pattern, migration: migration)
        }
    }

    /// Suggestions grouped by migration recipe, ordered for a work queue:
    /// auto-patchable first (quick wins), then by number of occurrences.
    func groupedByMigration(_ suggestions: [MigrationSuggestion]) -> [MigrationGroup] {
        Dictionary(grouping: suggestions, by: \.migrationID)
            .map { MigrationGroup(suggestions: $0.value) }
            .sorted { lhs, rhs in
                if lhs.complexity != rhs.complexity {
                    return lhs.complexity == .autoPatchable
                }
                if lhs.occurrences != rhs.occurrences {
                    return lhs.occurrences > rhs.occurrences
                }
                return lhs.migrationID < rhs.migrationID
            }
    }
}

/// Every occurrence of one migration recipe across the project.
struct MigrationGroup: Sendable {
    let representative: MigrationSuggestion
    /// Occurrences, ordered by file then line.
    let locations: [DetectedPattern]

    init(suggestions: [MigrationSuggestion]) {
        precondition(!suggestions.isEmpty, "A migration group needs at least one suggestion")
        self.representative = suggestions[0]
        self.locations = suggestions
            .map(\.pattern)
            .sorted { ($0.file, $0.line) < ($1.file, $1.line) }
    }

    var migrationID: String { representative.migrationID }
    var title: String { representative.title }
    var complexity: Complexity { representative.complexity }
    var patternType: PatternType { representative.pattern.patternType }
    var occurrences: Int { locations.count }
}
