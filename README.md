# AppIntentsMigrator

A Swift CLI tool to scan and migrate SiriKit code to App Intents (iOS 27).

## The Problem

SiriKit was deprecated at WWDC 2026. iOS 27 ships September 14, 2026 — 95 days away. If your app hasn't migrated to App Intents yet, your Siri integration will be **silently invisible** to every user on iOS 27.

The failure mode is insidious: SiriKit code compiles fine, passes tests, ships — and then users on iOS 27 can't find your app in Siri at all.

## What It Does

### Scan
Find all SiriKit patterns in your codebase:

```bash
$ app-intents-migrator scan ~/MyProject
SiriKit Patterns Found:
- INExtension subclasses: 3
- INIntent subclasses: 5
- Delegate methods: 4
Total patterns: 12
Files affected: 8
Report saved: migration_report.json
```

### Suggest
Get before/after code for each pattern:

```bash
$ app-intents-migrator suggest ~/MyProject
Pattern: INExtension subclass (line 12)

-- BEFORE (SiriKit) --
class MusicIntentHandler: INExtension {
  override func handler(for intent: INPlayMediaIntent) { ... }
}

-- AFTER (App Intents) --
struct PlayMediaIntent: AppIntent {
  static var title: LocalizedStringResource = "Play Media"
  func perform() async throws -> some IntentResult { ... }
}

Complexity: Manual review
Apple docs: https://developer.apple.com/documentation/appintents
```

## Installation

Clone and build:

```bash
git clone https://github.com/divyaravitech/AppIntentsMigrator.git
cd AppIntentsMigrator
swift build -c release
```

The binary is at `.build/release/app-intents-migrator`.

Or install with Homebrew (coming soon).

## Usage

### Scan your codebase
```bash
app-intents-migrator scan ~/MyProject
```

Outputs a summary + detailed `migration_report.json`.

### Get migration suggestions
```bash
app-intents-migrator suggest ~/MyProject
```

Shows before/after code for each pattern.

### Save to file
```bash
app-intents-migrator suggest ~/MyProject --output suggestions.json
app-intents-migrator scan ~/MyProject --output scan_report.json
```

### Summary only
```bash
app-intents-migrator scan ~/MyProject --summary
```

## What's Covered

22 SiriKit → App Intents migrations:
- INExtension classes → AppIntent structs
- INIntent subclasses → new AppIntent definitions
- resolve…(for:with:) → @Parameter declarations
- INInteraction donation → IntentDonationManager
- INVoiceShortcutCenter → new APIs
- AppShortcuts configuration
- Privacy manifest updates
- And 15 more...

Each with verified Apple documentation links.

## Roadmap

- [x] Phase 1: Scanner
- [x] Phase 2: Suggestion Engine
- [ ] Phase 3: Auto-patcher (safe mechanical migrations)
- [ ] Phase 4: Xcode plugin integration

## Requirements

- Swift 5.9+
- macOS 13+

## License

MIT

## Author

Divya Ravi
GitHub: [@divyaravitech](https://github.com/divyaravitech)

---

**The iOS 27 migration deadline is September 14. Don't get caught unprepared.**
