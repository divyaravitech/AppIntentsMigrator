import Foundation
import Testing
@testable import app_intents_migrator

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
