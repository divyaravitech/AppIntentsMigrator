import Testing
@testable import app_intents_migrator

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
