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
            "import Intents",
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
