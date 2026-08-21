# MigratedAppIntentsApp

`LegacySiriKitApp` after the migration — the same behaviour expressed in App Intents.

| Legacy | Here |
| --- | --- |
| `IntentHandler: INExtension` + `SendMessageIntentHandler` | `SendMessage.swift` — one `AppIntent` |
| `handle` / `confirm` / `resolve…` triple | a single `perform()` plus `@Parameter` declarations |
| `OrderCoffeeIntent: INIntent` with `@NSManaged` optionals | `OrderCoffee.swift` — typed, non-optional parameters and an `AppEnum` |
| `INVoiceShortcutCenter`, `INUIAddVoiceShortcutViewController`, `suggestedInvocationPhrase` | `AppShortcuts.swift` — a declared `AppShortcutsProvider` |
| `INInteraction(intent:response:).donate {}` | `IntentDonationManager.shared.donate(intent:)` |
| `INPreferences.requestSiriAuthorization` | nothing — no authorization step exists |

This is checked, not asserted. CI typechecks it against the real framework and requires the
scanner to report zero findings:

```bash
xcrun swiftc -typecheck -target arm64-apple-macos14 Examples/MigratedAppIntentsApp/*.swift
swift run app-intents-migrator scan Examples/MigratedAppIntentsApp
```

The stubs in `Support.swift` stand in for app code so the example compiles alone.
