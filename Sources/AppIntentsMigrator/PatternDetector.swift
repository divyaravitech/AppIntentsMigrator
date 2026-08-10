import Foundation

/// Finds legacy SiriKit constructs in Swift source text using line-oriented regular expressions.
struct PatternDetector: Sendable {

    /// A single regex-based detection rule.
    ///
    /// `NSRegularExpression` is immutable and documented as thread-safe for concurrent
    /// matching, but is not annotated `Sendable`, hence the unchecked conformance.
    struct Rule: @unchecked Sendable {
        let type: PatternType
        let id: RuleID
        let regex: NSRegularExpression
    }

    /// Rules in priority order. At most one finding is reported per line: the first
    /// rule that matches wins, so more specific rules are listed before broader ones
    /// (`class Handler: INExtension` is an INExtension finding, not a generic `IN…` reference).
    static let rules: [Rule] = [
        // MARK: INExtension
        rule(.inExtension, .inExtensionSubclass, #"\bclass\s+\w+\s*:[^{]*\bINExtension\b"#),

        // MARK: Legacy delegate / handler entry points
        rule(.delegateMethod, .handlerForIntent, #"\bfunc\s+handler\s*\(\s*for\s+\w+\s*:"#),
        rule(.delegateMethod, .handleIntent, #"\bfunc\s+handle\s*\(\s*\w+\s*:\s*IN\w+"#),
        rule(.delegateMethod, .confirmIntent, #"\bfunc\s+confirm\s*\(\s*\w+\s*:\s*IN\w+"#),
        rule(.delegateMethod, .resolveMethod, #"\bfunc\s+resolve\w*\s*\(\s*for\s+\w+\s*:\s*IN\w+"#),
        rule(.delegateMethod, .applicationHandlerFor, #"\bhandlerFor\s*\w*\s*:"#),
        rule(
            .delegateMethod,
            .appLaunchDelegate,
            #"\b(?:didFinishLaunchingWithOptions|willFinishLaunchingWithOptions|applicationDidFinishLaunching|applicationWillFinishLaunching)\b"#
        ),
        rule(.delegateMethod, .userActivityContinuation, #"\bfunc\s+application\s*\([^)]*\bcontinue\s+userActivity\b"#),

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
        rule(.otherSiriKit, .predictionEligibility, #"\bisEligibleFor(?:Prediction|Search|PublicIndexing|Handoff)\b"#),
        rule(.otherSiriKit, .infoPlistIntents, #"\b(?:IntentsSupported|IntentsRestrictedWhileLocked|INIntentsSupported)\b"#),
        rule(
            .otherSiriKit,
            .trackingAuthorization,
            #"\b(?:ATTrackingManager|requestTrackingAuthorization|NSUserTrackingUsageDescription|AppTrackingTransparency)\b"#
        ),
        rule(.otherSiriKit, .intentsFrameworkType, #"\bIN[A-Z]\w+\b"#),
    ]

    /// Scans `source` and returns every pattern found, ordered by line number.
    ///
    /// - Parameters:
    ///   - source: Full contents of a Swift file.
    ///   - file: Path recorded on each finding.
    func detect(in source: String, file: String) -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        var blockCommentDepth = 0

        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let code = Self.strippingComments(from: line, blockCommentDepth: &blockCommentDepth)
            guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            guard let (rule, match) = Self.firstMatch(in: code) else { continue }
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

    /// Returns the highest-priority rule matching `code`, along with the matched substring.
    private static func firstMatch(in code: String) -> (Rule, String)? {
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        for rule in rules {
            guard let match = rule.regex.firstMatch(in: code, options: [], range: range),
                  let matchRange = Range(match.range, in: code)
            else { continue }
            return (rule, String(code[matchRange]))
        }
        return nil
    }

    /// Blanks out comment text so that commented-out SiriKit code is not reported.
    ///
    /// Tracks nested `/* */` blocks across lines via `blockCommentDepth`. A `//` inside a
    /// string literal truncates the line early, which can hide a pattern on that line; that
    /// trade is deliberate, since the alternative is a full Swift lexer.
    private static func strippingComments(from line: String, blockCommentDepth: inout Int) -> String {
        let characters = Array(line)
        var result = ""
        var index = 0

        func matches(_ token: String) -> Bool {
            let token = Array(token)
            guard index + token.count <= characters.count else { return false }
            return Array(characters[index..<(index + token.count)]) == token
        }

        while index < characters.count {
            if blockCommentDepth > 0 {
                if matches("*/") {
                    blockCommentDepth -= 1
                    index += 2
                } else if matches("/*") {
                    blockCommentDepth += 1
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            if matches("/*") {
                blockCommentDepth += 1
                index += 2
                continue
            }
            if matches("//") {
                break
            }

            result.append(characters[index])
            index += 1
        }

        return result
    }

    /// Builds a rule from a literal pattern. The patterns are compile-time constants,
    /// so a failure here is a programming error rather than a runtime condition.
    private static func rule(_ type: PatternType, _ id: RuleID, _ pattern: String) -> Rule {
        // swiftlint:disable:next force_try
        Rule(type: type, id: id, regex: try! NSRegularExpression(pattern: pattern))
    }
}
