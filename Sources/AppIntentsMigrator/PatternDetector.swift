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
        var lexer = LexerState()

        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let code = Self.codeOnly(from: line, state: &lexer)
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

    /// Lexer position carried from one line to the next.
    struct LexerState {
        var blockCommentDepth = 0
        /// Number of `#` delimiters when inside a multi-line string literal; `nil` in code.
        var multilineStringHashes: Int?
    }

    /// Returns only the executable code on a line, with comments and string literal
    /// contents removed.
    ///
    /// Both are excluded for the same reason: SiriKit symbols appearing there are not code
    /// to migrate. Commented-out code should not be reported, and neither should the
    /// contents of a string — a documentation sample, a fixture, or a regex that happens to
    /// mention `INExtension` is text, not an API call. Patching such a line would edit the
    /// inside of a literal, which still parses, so validation could not catch the damage.
    ///
    /// Handles nested `/* */`, `//`, single-line and multi-line strings, and the raw forms
    /// (`#"…"#`, `#"""…"""#`) where the delimiter count decides what terminates the literal.
    static func codeOnly(from line: String, state: inout LexerState) -> String {
        let characters = Array(line)
        var result = ""
        var index = 0

        func matches(_ token: String, at position: Int) -> Bool {
            let token = Array(token)
            guard position + token.count <= characters.count else { return false }
            return Array(characters[position..<(position + token.count)]) == token
        }

        /// Number of consecutive `#` starting at `position`.
        func hashRun(at position: Int) -> Int {
            var count = 0
            while position + count < characters.count, characters[position + count] == "#" { count += 1 }
            return count
        }

        /// True when a multi-line literal closes here: `"""` followed by exactly `hashes` `#`.
        func closesMultiline(at position: Int, hashes: Int) -> Bool {
            guard matches("\"\"\"", at: position) else { return false }
            return hashRun(at: position + 3) >= hashes
        }

        while index < characters.count {
            // Inside a multi-line string: consume until the matching delimiter.
            if let hashes = state.multilineStringHashes {
                if closesMultiline(at: index, hashes: hashes) {
                    state.multilineStringHashes = nil
                    index += 3 + hashes
                } else {
                    index += 1
                }
                continue
            }

            if state.blockCommentDepth > 0 {
                if matches("*/", at: index) {
                    state.blockCommentDepth -= 1
                    index += 2
                } else if matches("/*", at: index) {
                    state.blockCommentDepth += 1
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            if matches("//", at: index) { break }
            if matches("/*", at: index) {
                state.blockCommentDepth += 1
                index += 2
                continue
            }

            // A string literal opens with optional `#`s then a quote.
            let hashes = hashRun(at: index)
            let quoteIndex = index + hashes
            if quoteIndex < characters.count, characters[quoteIndex] == "\"" {
                if matches("\"\"\"", at: quoteIndex) {
                    state.multilineStringHashes = hashes
                    index = quoteIndex + 3
                } else {
                    index = endOfSingleLineString(characters, openingQuote: quoteIndex, hashes: hashes)
                }
                continue
            }

            result.append(characters[index])
            index += 1
        }

        return result
    }

    /// Index just past the closing quote of a single-line string, or the end of the line
    /// when the literal is unterminated.
    private static func endOfSingleLineString(_ characters: [Character], openingQuote: Int, hashes: Int) -> Int {
        var index = openingQuote + 1

        while index < characters.count {
            // Escapes only apply in non-raw strings; in raw strings the escape is `\#…`.
            if characters[index] == "\\", hashes == 0 {
                index += 2
                continue
            }
            if characters[index] == "\"" {
                var closingHashes = 0
                while index + 1 + closingHashes < characters.count,
                      characters[index + 1 + closingHashes] == "#" {
                    closingHashes += 1
                }
                if closingHashes >= hashes { return index + 1 + hashes }
            }
            index += 1
        }

        return characters.count
    }

    /// Builds a rule from a literal pattern. The patterns are compile-time constants,
    /// so a failure here is a programming error rather than a runtime condition.
    private static func rule(_ type: PatternType, _ id: RuleID, _ pattern: String) -> Rule {
        // swiftlint:disable:next force_try
        Rule(type: type, id: id, regex: try! NSRegularExpression(pattern: pattern))
    }
}
