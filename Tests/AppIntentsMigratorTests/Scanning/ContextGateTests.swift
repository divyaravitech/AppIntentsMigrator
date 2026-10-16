import Testing
@testable import app_intents_migrator

@Suite("SiriKit context")
struct ContextGateTests {

    /// `didFinishLaunching` and `func resolveSomething(` are ordinary Swift. Reporting them
    /// in an app that never imported Intents is worse than missing them, so these rules
    /// only fire when the file actually references SiriKit.
    @Test("Generic Swift is not reported without SiriKit in the file")
    func genericSwiftIsIgnored() {
        #expect(rulesFired(in: "func resolveMembers(in id: String) -> [String] { [] }").isEmpty)
        #expect(rulesFired(in: "func application(_ a: UIApplication, didFinishLaunchingWithOptions o: Any?) -> Bool { true }").isEmpty)
        #expect(rulesFired(in: "func scene(_ s: UIScene, continue userActivity: NSUserActivity) {}").isEmpty)
    }

    @Test("The same code is reported when the file uses SiriKit")
    func reportedWithContext() {
        let withImport = ["import Intents", "func resolveMembers(in id: String) -> [String] { [] }"]
            .joined(separator: "\n")
        #expect(rulesFired(in: withImport).contains(.resolveMethod))

        let withSymbol = ["func resolveRecipients(", "    for intent: INSendMessageIntent,", ") {}"]
            .joined(separator: "\n")
        #expect(rulesFired(in: withSymbol).contains(.resolveMethod))
    }

    @Test("Identifiers that merely start with IN are not SiriKit")
    func inPrefixedIdentifiersAreNotContext() {
        #expect(!PatternDetector.hasSiriKitContext("let INFO = 1; INSERT INTEGER"))
        #expect(PatternDetector.hasSiriKitContext("let x: INExtension? = nil"))
    }
}
