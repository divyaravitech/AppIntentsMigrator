import Foundation

/// The rewrite rules the auto-patcher is allowed to consider.
///
/// Two tiers, and the distinction is the whole point of this phase:
///
/// - `.automatic` rules are line-local and semantics-preserving. A line matches, it is
///   replaced or deleted, and nothing outside that line is affected. Every automatic rule
///   corresponds to a `MigrationPattern` marked `.autoPatchable` — enforced by
///   `inconsistentRules`.
/// - `.proposalOnly` rules are structural. Text substitution can produce the new signature
///   but not the new *body*, so the result does not compile without human work. They are
///   shown in dry runs and only written when the caller explicitly opts in.
enum PatchingRules {

    /// What a matching rule does to the line.
    enum Action: Sendable {
        /// Replace the whole line using a regex template (`$1`, `$2`, …).
        case replaceLine(template: String)
        /// Remove the line entirely.
        case deleteLine
    }

    struct Rule: @unchecked Sendable {
        let id: String
        /// Scanner rule this answers; a line is only considered if the scanner flagged it with this.
        let rule: RuleID
        let safety: PatchSafety
        /// One-line description of the rewrite, shown in reports.
        let summary: String
        let regex: NSRegularExpression
        let action: Action
        /// When true, the line is skipped unless its braces, parens and brackets are balanced
        /// and it contains no trailing continuation — protection against deleting the opening
        /// line of a multi-line statement.
        let requiresSelfContainedLine: Bool
        /// Why a structural rule cannot be applied safely. `nil` for automatic rules.
        let manualReason: String?
    }

    // MARK: - Rules

    static let all: [Rule] = [

        // MARK: Automatic — line-local, semantics-preserving

        rule(
            id: "swap-intents-import",
            rule: .intentsImport,
            safety: .automatic,
            summary: "import Intents / IntentsUI → import AppIntents",
            pattern: #"^(\s*)import\s+Intents(?:UI)?\s*$"#,
            action: .replaceLine(template: "$1import AppIntents")
        ),

        rule(
            id: "drop-siri-authorization",
            rule: .siriAuthorization,
            safety: .automatic,
            summary: "Delete INPreferences authorization call (App Intents needs no prompt)",
            pattern: #"^\s*INPreferences\s*\.\s*(?:requestSiriAuthorization|siriAuthorizationStatus)\b"#,
            action: .deleteLine,
            requiresSelfContainedLine: true
        ),

        rule(
            id: "drop-prediction-flag",
            rule: .predictionEligibility,
            safety: .automatic,
            summary: "Delete NSUserActivity prediction flag (superseded by intent donations)",
            pattern: #"^\s*[\w.]+\.isEligibleForPrediction\s*=\s*true\s*$"#,
            action: .deleteLine,
            requiresSelfContainedLine: true
        ),

        // MARK: Proposal only — structural rewrites that need a human

        rule(
            id: "inextension-class-to-struct",
            rule: .inExtensionSubclass,
            safety: .proposalOnly,
            summary: "class X: INExtension → struct X: AppIntent",
            pattern: #"^(\s*)(?:(?:public|internal|private|fileprivate|final|open)\s+)*class\s+(\w+)\s*:\s*INExtension\b.*$"#,
            action: .replaceLine(template: "$1struct $2: AppIntent {"),
            manualReason: """
            Changes a class to a struct: reference semantics become value semantics, \
            `override` members in the body become invalid, and stored state mutated by \
            methods needs `mutating`. Any extra conformances on the original line are \
            dropped. The body still contains handler-lookup code that has no meaning in \
            an AppIntent.
            """
        ),

        rule(
            id: "handler-for-to-perform",
            rule: .handlerForIntent,
            safety: .proposalOnly,
            summary: "func handler(for:) → func perform() async throws",
            pattern: #"^(\s*)(?:override\s+)?func\s+handler\s*\(\s*for\s+\w+\s*:[^)]*\)\s*->\s*Any\?\s*\{\s*$"#,
            action: .replaceLine(template: "$1func perform() async throws -> some IntentResult {"),
            manualReason: """
            The body returns handler objects (`return SendMessageHandler()`), which is not \
            a valid `some IntentResult`. Every `return` in the method must be rewritten, \
            and the dispatch switch must be split into one AppIntent per case.
            """
        ),

        rule(
            id: "inintent-subclass-to-appintent",
            rule: .customIntentSubclass,
            safety: .proposalOnly,
            summary: "class X: INIntent → struct X: AppIntent",
            pattern: #"^(\s*)(?:(?:public|internal|private|fileprivate|final|open)\s+)*class\s+(\w+)\s*:\s*IN\w*Intent\b.*$"#,
            action: .replaceLine(template: "$1struct $2: AppIntent {"),
            manualReason: """
            AppIntent requires a static `title` and a `perform()`, neither of which exists \
            in the generated class. `@NSManaged` properties must become `@Parameter` \
            declarations with real types, and the originating .intentdefinition file has \
            to be removed from the target.
            """
        ),

        rule(
            id: "didfinishlaunching-to-perform",
            rule: .appLaunchDelegate,
            safety: .proposalOnly,
            summary: "application(_:didFinishLaunchingWithOptions:) → perform() async throws",
            pattern: #"^(\s*)func\s+application\s*\([^)]*didFinishLaunchingWithOptions[^)]*\)\s*->\s*Bool\s*\{\s*$"#,
            action: .replaceLine(template: "$1func perform() async throws -> some IntentResult {"),
            manualReason: """
            This is your app's launch entry point, not an intent. Rewriting the signature \
            deletes app startup and leaves `return true` returning from a function that \
            must return `some IntentResult`. Only the SiriKit-specific statements inside \
            it should move to an intent; the method itself must stay.
            """
        ),
    ]

    // MARK: - Lookup

    static func rules(for pattern: DetectedPattern, allowingProposals: Bool) -> [Rule] {
        all.filter { candidate in
            candidate.rule == pattern.rule
                && (allowingProposals || candidate.safety == .automatic)
        }
    }

    /// Automatic rules whose migration is not marked `.autoPatchable`.
    ///
    /// Always empty: the safety tier here and the complexity in `CommonPatterns` must agree,
    /// or the patcher would write a change the guide calls manual. Exposed so it is testable.
    static var inconsistentRules: [String] {
        all.compactMap { rule in
            guard rule.safety == .automatic else { return nil }
            guard let migration = CommonPatterns.byRule[rule.rule] else { return rule.id }
            return migration.complexity == .autoPatchable ? nil : rule.id
        }
    }

    // MARK: - Application

    /// Applies `rule` to `line`, returning the new text (`nil` means delete the line),
    /// or `.none` when the rule does not match.
    static func apply(_ rule: Rule, to line: String) -> (replacement: String?, matched: Bool) {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard rule.regex.firstMatch(in: line, options: [], range: range) != nil else {
            return (nil, false)
        }
        if rule.requiresSelfContainedLine, !isSelfContained(line) {
            return (nil, false)
        }

        switch rule.action {
        case .deleteLine:
            return (nil, true)
        case .replaceLine(let template):
            let replaced = rule.regex.stringByReplacingMatches(
                in: line, options: [], range: range, withTemplate: template
            )
            return (replaced, true)
        }
    }

    /// True when every bracket opened on the line is also closed on it, so removing the
    /// line cannot orphan a block. Brackets inside string literals are ignored.
    static func isSelfContained(_ line: String) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false

        for character in line {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "\"" { inString.toggle(); continue }
            guard !inString else { continue }

            switch character {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth -= 1
            default: break
            }
            if depth < 0 { return false }
        }

        return depth == 0 && !inString
    }

    private static func rule(
        id: String,
        rule: RuleID,
        safety: PatchSafety,
        summary: String,
        pattern: String,
        action: Action,
        requiresSelfContainedLine: Bool = false,
        manualReason: String? = nil
    ) -> Rule {
        // swiftlint:disable:next force_try
        Rule(
            id: id,
            rule: rule,
            safety: safety,
            summary: summary,
            regex: try! NSRegularExpression(pattern: pattern),
            action: action,
            requiresSelfContainedLine: requiresSelfContainedLine,
            manualReason: manualReason
        )
    }
}
