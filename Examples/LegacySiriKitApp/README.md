# LegacySiriKitApp

A deliberately un-migrated SiriKit app, for exercising the migrator end to end.

It is **sample source, not a buildable Xcode project** — there is no `.xcodeproj`, and the
files import `Intents`/`UIKit`, so they are not compiled by this package. They exist to be
scanned, and they trigger **all 22 detection rules**.

## What's in it

| Path | Legacy pattern |
| --- | --- |
| `App/AppDelegate.swift` | `didFinishLaunching`, `INPreferences` authorization, `continue userActivity`, `application(_:handlerFor:)`, `INVocabulary` |
| `App/ShortcutDonations.swift` | `INInteraction` donation, `suggestedInvocationPhrase`, prediction flags, `INVoiceShortcutCenter` |
| `App/AddShortcutViewController.swift` | `IntentsUI` — `INUIAddVoiceShortcutViewController` |
| `App/Analytics.swift` | `ATTrackingManager` (privacy manifest) |
| `IntentsExtension/IntentHandler.swift` | `INExtension`, `handler(for:)` dispatch |
| `IntentsExtension/SendMessageIntentHandler.swift` | `IN…IntentHandling`, `resolve…`/`confirm`/`handle`, resolution results |
| `IntentsExtension/Info.plist` | `IntentsSupported`, `IntentsRestrictedWhileLocked`, `NSSiriUsageDescription`, intents extension point |
| `Generated/OrderCoffeeIntent.swift` | `INIntent` subclass as generated from a `.intentdefinition` |

## Try it

```bash
swift run app-intents-migrator scan Examples/LegacySiriKitApp
```

```bash
swift run app-intents-migrator suggest Examples/LegacySiriKitApp
```

```bash
swift run app-intents-migrator patch Examples/LegacySiriKitApp --dry-run
```

The dry run changes little on purpose: nearly everything here is structural, so it lands in
`suggest`. Note that the import swaps are reported as *deferred* — every file still uses
SiriKit symbols that need `import Intents`.

To see the patcher actually write, and then undo it:

```bash
swift run app-intents-migrator patch Examples/LegacySiriKitApp --include-structural
```

```bash
git checkout Examples/LegacySiriKitApp
```
