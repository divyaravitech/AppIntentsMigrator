import Testing
@testable import app_intents_migrator

@Suite("Migration library")
struct CommonPatternsTests {

    @Test("Every detection rule has a migration")
    func everyRuleIsMapped() {
        #expect(CommonPatterns.unmappedRules.isEmpty)
    }

    @Test("Every migration links to Apple documentation")
    func everyMigrationHasDocs() {
        for migration in CommonPatterns.byPatternType.values.flatMap({ $0 }) {
            #expect(
                migration.appleDocLink.hasPrefix("https://developer.apple.com/"),
                "\(migration.id) has a non-Apple link"
            )
        }
    }

    @Test("Every migration shows before and after code with a rationale")
    func everyMigrationHasExamples() {
        for migration in CommonPatterns.byPatternType.values.flatMap({ $0 }) {
            #expect(!migration.beforeCode.isEmpty, "\(migration.id) has no before code")
            #expect(!migration.afterCode.isEmpty, "\(migration.id) has no after code")
            #expect(!migration.explanation.isEmpty, "\(migration.id) has no explanation")
        }
    }

    @Test("No finding is dropped when generating suggestions")
    func suggestionsCoverEveryFinding() {
        let patterns = RuleID.allCases.map {
            DetectedPattern(patternType: .otherSiriKit, file: "F.swift", line: 1, code: "", match: "", rule: $0)
        }
        #expect(SuggestionGenerator().generateSuggestions(patterns: patterns).count == patterns.count)
    }
}
