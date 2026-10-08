import Foundation

/// Finds legacy SiriKit constructs in Swift source text using line-oriented regular expressions.
struct PatternDetector: Sendable {

    /// A single regex-based detection rule.
    struct Rule: @unchecked Sendable {
        let type: PatternType
        let id: RuleID
        let regex: NSRegularExpression
        /// Matches ordinary Swift that only means SiriKit when the file uses SiriKit.
        /// `didFinishLaunching` and `func resolveSomething(` exist in apps that have never
        /// imported Intents, and reporting those is worse than missing them.
        let needsContext: Bool
    }

    /// Unambiguous SiriKit references. Deliberately not `IN[A-Z]\w+`, which also matches
    /// identifiers like INFO and INSERT.
    private static let siriKitContext: NSRegularExpression = {
        let alternatives = [
            #"\bimport\s+Intents(?:UI)?\b"#,
            #"\bINExtension\b"#,
            #"\bIN\w*Intent(?:Handling|Response)?\b"#,
            #"\bIN\w*ResolutionResult\b"#,
            #"\bINPreferences\b"#,
            #"\bINInteraction\b"#,
            #"\bINVoiceShortcut\w*\b"#,
            #"\bINMediaItem\b"#,
            #"\bINMediaSearch\b"#,
            #"\bINShortcut\b"#,
            #"\bINVocabulary\b"#,
        ]
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: alternatives.joined(separator: "|"))
    }()

    static func hasSiriKitContext(_ code: String) -> Bool {
        siriKitContext.firstMatch(in: code, range: NSRange(code.startIndex..<code.endIndex, in: code)) != nil
    }

    /// Rules in priority order. At most one finding is reported per line: the first
    /// rule that matches wins, so more specific rules are listed before broader ones
    /// (`class Handler: INExtension` is an INExtension finding, not a generic `IN…` reference).
    static let rules: [Rule] = [
        // MARK: INExtension
        rule(.inExtension, .inExtensionSubclass, #"\bclass\s+\w+\s*:[^{]*\bINExtension\b"#),

        // MARK: Legacy delegate / handler entry points
        rule(.delegateMethod, .handlerForIntent, needsContext: true, #"\bfunc\s+handler\s*\(\s*for\s+\w+\s*:"#),
        rule(.delegateMethod, .handleIntent, #"\bfunc\s+handle\s*\(\s*\w+\s*:\s*IN\w+"#),
        rule(.delegateMethod, .confirmIntent, #"\bfunc\s+confirm\s*\(\s*\w+\s*:\s*IN\w+"#),
        // Matched on the `func` line alone rather than the whole signature: real code wraps
        // these across lines, and a rule spanning the parameter list would never fire.
        rule(.delegateMethod, .resolveMethod, needsContext: true, #"\bfunc\s+resolve[A-Z]\w*\s*\("#),
        rule(.delegateMethod, .applicationHandlerFor, needsContext: true, #"\bhandlerFor\s*\w*\s*:"#),
        rule(
            .delegateMethod,
            .appLaunchDelegate,
            needsContext: true,
            #"\b(?:didFinishLaunchingWithOptions|willFinishLaunchingWithOptions|applicationDidFinishLaunching|applicationWillFinishLaunching)\b"#
        ),
        rule(.delegateMethod, .userActivityContinuation, needsContext: true, #"\bcontinue\s+userActivity\s*:"#),

        // MARK: Intents
        rule(.inIntent, .customIntentSubclass, #"\bclass\s+\w+\s*:[^{]*\bIN\w*Intent\b"#),
        rule(.inIntent, .intentHandlingProtocol, #"\bIN\w*IntentHandling\b"#),
        rule(.inIntent, .resolutionResult, #"\bIN\w*ResolutionResult\b"#),
        rule(.inExtension, .inExtensionReference, #"\bINExtension\b"#),
        rule(.inIntent, .intentTypeReference, #"\bIN\w*Intent(?:Response)?\b"#),

        // MARK: Everything else from Intents / IntentsUI
        rule(.otherSiriKit, .intentsImport, #"^\s*(?:@\w+\s+)*import\s+Intents(?:UI)?\b"#),
        rule(.otherSiriKit, .interactionDonation, #"\bINInteraction\b"#),
        rule(
            .otherSiriKit,
            .voiceShortcutAPI,
            #"\b(?:INVoiceShortcutCenter|INVoiceShortcut|INShortcut|INUIAddVoiceShortcut\w*|INUIEditVoiceShortcut\w*)\b"#
        ),
        rule(.otherSiriKit, .siriAuthorization, #"\b(?:INPreferences|INSiriAuthorizationStatus)\b"#),
        rule(.otherSiriKit, .invocationPhrase, #"\bsuggestedInvocationPhrase\b"#),
        // Only the prediction flag. isEligibleForSearch and isEligibleForPublicIndexing are
        // Spotlight indexing, and isEligibleForHandoff is Handoff — all still supported and
        // none part of this migration.
        rule(.otherSiriKit, .predictionEligibility, #"\bisEligibleForPrediction\b"#),
        rule(.otherSiriKit, .infoPlistIntents, #"\b(?:IntentsSupported|IntentsRestrictedWhileLocked|INIntentsSupported)\b"#),
        rule(
            .privacy,
            .trackingAuthorization,
            #"\b(?:ATTrackingManager|requestTrackingAuthorization|NSUserTrackingUsageDescription|AppTrackingTransparency)\b"#
        ),
        rule(.otherSiriKit, .intentsFrameworkType, #"\bIN[A-Z]\w+\b"#),
    ]

    /// Scans `source` and returns every pattern found, ordered by line number.
    func detect(in source: String, file: String) -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let strippedSource = SwiftCode.strippingCommentsAndLiterals(from: source)
        let stripped = SourceLines.split(strippedSource)
        let siriKitFile = Self.hasSiriKitContext(strippedSource)

        // A declaration wrapped across lines is one site, not several. Only parentheses and
        var openDepth = 0
        var rulesInDeclaration: Set<RuleID> = []

        for (index, sourceLine) in SourceLines.split(source).enumerated() {
            let line = sourceLine.text
            let code = index < stripped.count ? stripped[index].text : ""
            guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            let isContinuation = openDepth > 0
            defer {
                openDepth = max(0, openDepth + Self.bracketDelta(of: code))
                if openDepth == 0 { rulesInDeclaration.removeAll() }
            }

            guard let (rule, match) = Self.firstMatch(in: code, allowContextual: siriKitFile) else { continue }
            // The same rule firing again on a continuation line is the same finding.
            guard !(isContinuation && rulesInDeclaration.contains(rule.id)) else { continue }
            rulesInDeclaration.insert(rule.id)

            patterns.append(
                DetectedPattern(
                    patternType: rule.type,
                    file: file,
                    line: index + 1,
                    code: line.trimmingCharacters(in: .whitespaces),
                    match: match,
                    rule: rule.id
                )
            )
        }

        return patterns
    }

    /// Net change in parenthesis and bracket nesting across a line of code.
    private static func bracketDelta(of code: String) -> Int {
        code.reduce(into: 0) { depth, character in
            switch character {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            default: break
            }
        }
    }

    // MARK: - Property lists

    /// Rules for `Info.plist`, where SiriKit is declared rather than called.
    static let propertyListRules: [Rule] = [
        rule(.inExtension, .inExtensionReference, #"com\.apple\.intents(?:-ui)?-service"#),
        rule(.otherSiriKit, .infoPlistIntents, #"\b(?:IntentsSupported|IntentsRestrictedWhileLocked)\b"#),
        rule(.otherSiriKit, .siriAuthorization, #"\bNSSiriUsageDescription\b"#),
        rule(.inIntent, .intentTypeReference, #"\bIN\w*Intent\b"#),
    ]

    /// Scans a property list for SiriKit declarations.
    func detectInPropertyList(in source: String, file: String) -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        var insideComment = false

        for (index, sourceLine) in SourceLines.split(source).enumerated() {
            let line = sourceLine.text
            let code = Self.strippingXMLComments(from: line, insideComment: &insideComment)
            guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            guard let (rule, match) = Self.firstMatch(in: code, rules: Self.propertyListRules) else { continue }
            patterns.append(
                DetectedPattern(
                    patternType: rule.type,
                    file: file,
                    line: index + 1,
                    code: line.trimmingCharacters(in: .whitespaces),
                    match: match,
                    rule: rule.id
                )
            )
        }

        return patterns
    }

    /// Removes `<!-- … -->` content, tracking comments that span lines.
    private static func strippingXMLComments(from line: String, insideComment: inout Bool) -> String {
        var remainder = Substring(line)
        var result = ""

        while !remainder.isEmpty {
            if insideComment {
                guard let end = remainder.range(of: "-->") else { return result }
                remainder = remainder[end.upperBound...]
                insideComment = false
                continue
            }
            guard let start = remainder.range(of: "<!--") else {
                result += remainder
                break
            }
            result += remainder[..<start.lowerBound]
            remainder = remainder[start.upperBound...]
            insideComment = true
        }

        return result
    }

    /// Returns the highest-priority rule matching `code`, along with the matched substring.
    private static func firstMatch(
        in code: String,
        rules: [Rule] = rules,
        allowContextual: Bool = true
    ) -> (Rule, String)? {
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        for rule in rules where allowContextual || !rule.needsContext {
            guard let match = rule.regex.firstMatch(in: code, options: [], range: range),
                  let matchRange = Range(match.range, in: code)
            else { continue }
            return (rule, String(code[matchRange]))
        }
        return nil
    }

    /// Patterns are compile-time constants, so a bad one is a programming error.
    private static func rule(
        _ type: PatternType,
        _ id: RuleID,
        needsContext: Bool = false,
        _ pattern: String
    ) -> Rule {
        // swiftlint:disable:next force_try
        Rule(type: type, id: id, regex: try! NSRegularExpression(pattern: pattern), needsContext: needsContext)
    }
}
