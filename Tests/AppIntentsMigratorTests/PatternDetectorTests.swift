import Testing
@testable import app_intents_migrator

@Suite("Pattern detection")
struct PatternDetectorTests {

    @Test("Finds an INExtension subclass")
    func findsINExtensionSubclass() {
        #expect(rulesFired(in: "class IntentHandler: INExtension {") == [.inExtensionSubclass])
    }

    @Test("Reports one finding per line, highest priority first")
    func onePerLineByPriority() {
        // The line names INExtension and an intent-handling protocol; INExtension wins.
        #expect(rulesFired(in: "class H: INExtension, INSendMessageIntentHandling {") == [.inExtensionSubclass])
    }

    // MARK: Comments

    @Test("Ignores commented-out code")
    func ignoresComments() {
        #expect(rulesFired(in: "// class X: INExtension {}").isEmpty)
        #expect(rulesFired(in: "let a = 1 // INPreferences.requestSiriAuthorization").isEmpty)
        #expect(rulesFired(in: "/* class X: INExtension {}\nstill a comment\n*/").isEmpty)
    }

    // MARK: String literals
    //
    // The regression that matters. SiriKit inside a literal is documentation or fixture
    // text, and patching such a line edits the inside of a string — which still parses, so
    // the validator could not catch the damage.

    @Test("Ignores single-line string literals")
    func ignoresStringLiterals() {
        #expect(rulesFired(in: "let doc = \"class X: INExtension {}\"").isEmpty)
        #expect(rulesFired(in: "let raw = #\"INPreferences.foo()\"#").isEmpty)
        #expect(rulesFired(in: "let esc = \"he said \\\"INExtension\\\"\"").isEmpty)
    }

    @Test("Ignores multi-line string literals")
    func ignoresMultilineStrings() {
        let plain = ["let s = \"\"\"", "class Sample: INExtension {}", "\"\"\""].joined(separator: "\n")
        #expect(rulesFired(in: plain).isEmpty)
    }

    @Test("Ignores raw multi-line string literals")
    func ignoresRawMultilineStrings() {
        let raw = ["let s = #\"\"\"", "import Intents", "\"\"\"#"].joined(separator: "\n")
        #expect(rulesFired(in: raw).isEmpty)
    }

    @Test("A URL inside a string does not truncate the line")
    func urlInStringIsNotAComment() {
        #expect(rulesFired(in: "let u = \"https://example.com\"").isEmpty)
    }

    @Test("Code after a string on the same line is still detected")
    func detectsCodeFollowingAString() {
        #expect(rulesFired(in: "print(\"hi\"); let x: INExtension? = nil") == [.inExtensionReference])
        #expect(rulesFired(in: "let m = \"t\" + String(describing: INPreferences.self)") == [.siriAuthorization])
    }

    // MARK: Wrapped signatures

    @Test("Finds a resolve method whose signature wraps across lines")
    func findsWrappedResolveMethod() {
        let source = [
            "func resolveRecipients(",
            "    for intent: INSendMessageIntent,",
            "    with completion: @escaping (Any) -> Void",
            ") {",
        ].joined(separator: "\n")
        #expect(rulesFired(in: source).contains(.resolveMethod))
    }

    @Test("Finds a wrapped NSUserActivity continuation")
    func findsWrappedUserActivityContinuation() {
        let source = [
            "func application(",
            "    _ application: UIApplication,",
            "    continue userActivity: NSUserActivity,",
            "    restorationHandler: @escaping (Any) -> Void",
            ") -> Bool {",
        ].joined(separator: "\n")
        #expect(rulesFired(in: source).contains(.userActivityContinuation))
    }

    // MARK: Property lists

    @Test("Finds SiriKit declarations in a property list")
    func findsPropertyListDeclarations() {
        let plist = [
            "<key>NSSiriUsageDescription</key>",
            "<key>IntentsSupported</key>",
            "<string>INSendMessageIntent</string>",
            "<string>com.apple.intents-service</string>",
        ].joined(separator: "\n")

        let fired = PatternDetector().detectInPropertyList(in: plist, file: "Info.plist").map(\.rule)
        #expect(fired == [.siriAuthorization, .infoPlistIntents, .intentTypeReference, .inExtensionReference])
    }

    @Test("Ignores XML comments in a property list")
    func ignoresXMLComments() {
        let plist = "<!-- <key>IntentsSupported</key> -->"
        #expect(PatternDetector().detectInPropertyList(in: plist, file: "Info.plist").isEmpty)
    }
}

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

@Suite("Patching rules")
struct PatchingRulesTests {

    @Test("Automatic rules only ever map to AutoPatchable migrations")
    func automaticRulesAreAutoPatchable() {
        #expect(PatchingRules.inconsistentRules.isEmpty)
    }

    @Test("Structural rules explain why a human is needed")
    func structuralRulesCarryReasons() {
        for rule in PatchingRules.all where rule.safety == .proposalOnly {
            #expect(rule.manualReason?.isEmpty == false, "\(rule.id) has no manual reason")
        }
    }

    @Test("Self-contained line detection guards multi-line deletions")
    func detectsSelfContainedLines() {
        #expect(PatchingRules.isSelfContained("INPreferences.requestSiriAuthorization { _ in }"))
        #expect(!PatchingRules.isSelfContained("INPreferences.requestSiriAuthorization { status in"))
        #expect(PatchingRules.isSelfContained("let s = \"unbalanced { brace in a string\""))
    }
}

@Suite("NSUserActivity flags")
struct ActivityFlagTests {

    /// Found against LoopKit/Loop, which sets these three together. Deleting an explicit
    /// `= false` reverts the property to its default and flips behaviour, and Handoff and
    /// Spotlight indexing are not part of the App Intents migration at all.
    @Test("Only the prediction flag is a migration finding")
    func onlyPredictionIsFlagged() {
        #expect(rulesFired(in: "activity.isEligibleForPrediction = true") == [.predictionEligibility])
        #expect(rulesFired(in: "activity.isEligibleForSearch = true").isEmpty)
        #expect(rulesFired(in: "activity.isEligibleForHandoff = false").isEmpty)
        #expect(rulesFired(in: "activity.isEligibleForPublicIndexing = false").isEmpty)
    }

    @Test("Only `= true` is auto-deletable")
    func onlyTrueIsPatchable() {
        let rule = PatchingRules.all.first { $0.id == "drop-prediction-flag" }!

        #expect(PatchingRules.apply(rule, to: "    activity.isEligibleForPrediction = true").matched)
        // Deleting this would silently re-enable prediction.
        #expect(!PatchingRules.apply(rule, to: "    activity.isEligibleForPrediction = false").matched)
        #expect(!PatchingRules.apply(rule, to: "    activity.isEligibleForHandoff = false").matched)
    }
}
