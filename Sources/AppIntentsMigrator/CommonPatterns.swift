import Foundation

/// The single source of truth for SiriKit → App Intents migration advice.
///
/// Every `RuleID` the detector can emit maps to exactly one `MigrationPattern` here,
/// so a new detection rule cannot ship without migration guidance (see `unmappedRules`).
///
/// **Provenance:** guidance is derived from Apple's published App Intents framework
/// documentation. Every `appleDocLink` below was checked against Apple's documentation
/// API and returns a live page. Sessions from WWDC26 are *not* reflected here — if that
/// material changes any recommendation, this file is the only place to update.
enum CommonPatterns {

    // MARK: - Lookup

    /// Every migration recipe, keyed by the detection rule it answers.
    static let byRule: [RuleID: MigrationPattern] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.rule, $0.pattern) }
    )

    /// Migration recipes grouped by scanner category.
    static let byPatternType: [PatternType: [MigrationPattern]] = Dictionary(
        grouping: all.map(\.pattern), by: \.patternType
    )

    /// The recipe for a finding. Total: every rule is mapped.
    static func migration(for pattern: DetectedPattern) -> MigrationPattern? {
        byRule[pattern.rule]
    }

    /// Rules with no migration mapped. Always empty; exists so the invariant is testable.
    static var unmappedRules: [RuleID] {
        RuleID.allCases.filter { byRule[$0] == nil }
    }

    // MARK: - The library

    private static let all: [(rule: RuleID, pattern: MigrationPattern)] = [

        // MARK: INExtension class → AppIntent struct
        (.inExtensionSubclass, MigrationPattern(
            id: "inextension-to-appintent",
            title: "INExtension class → AppIntent struct",
            patternType: .inExtension,
            beforeCode: #"""
            // IntentHandler.swift — the Intents extension principal class
            class IntentHandler: INExtension {
                override func handler(for intent: INIntent) -> Any? {
                    guard intent is INSendMessageIntent else { return nil }
                    return SendMessageIntentHandler()
                }
            }
            """#,
            afterCode: #"""
            // No principal class and no handler lookup: the intent is the implementation.
            struct SendMessage: AppIntent {
                static let title: LocalizedStringResource = "Send Message"

                @Parameter(title: "Recipient") var recipient: String
                @Parameter(title: "Message") var message: String

                func perform() async throws -> some IntentResult {
                    try await MessageService.shared.send(message, to: recipient)
                    return .result()
                }
            }
            """#,
            explanation: """
            INExtension existed only to route an INIntent to a separate handler object. \
            App Intents collapses that indirection: one struct declares its parameters, \
            its metadata, and its behaviour. Put the type in your app target so it shares \
            your app's code and state, or in an extension adopting AppIntentsExtension if \
            it must run out of process. The old Intents extension target and its \
            .intentdefinition file can be deleted once every intent is migrated.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/appintent"
        )),

        (.inExtensionReference, MigrationPattern(
            id: "inextension-reference",
            title: "INExtension reference → App Intents target layout",
            patternType: .inExtension,
            beforeCode: #"""
            // Info.plist of the Intents extension
            // NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).IntentHandler
            let handler: INExtension = IntentHandler()
            """#,
            afterCode: #"""
            // App Intents are discovered from your compiled code — no principal class,
            // no NSExtension plist wiring.
            struct MyIntentsExtension: AppIntentsExtension {}
            """#,
            explanation: """
            Any remaining reference to INExtension is part of the old extension wiring. \
            App Intents are found by the system through metadata the compiler emits, so \
            there is nothing to register. Adopt AppIntentsExtension only when you need \
            intents to execute outside your app's process.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/appintentsextension"
        )),

        // MARK: handler(for:) → AppIntent.perform()
        (.handlerForIntent, MigrationPattern(
            id: "handler-for-to-perform",
            title: "handler(for:) → AppIntent.perform()",
            patternType: .delegateMethod,
            beforeCode: #"""
            override func handler(for intent: INIntent) -> Any? {
                switch intent {
                case is INSendMessageIntent:      return SendMessageHandler()
                case is INSearchForMessagesIntent: return SearchMessagesHandler()
                default:                           return nil
                }
            }
            """#,
            afterCode: #"""
            // The switch becomes one self-contained type per operation.
            struct SendMessage: AppIntent {
                func perform() async throws -> some IntentResult { /* ... */ .result() }
            }

            struct SearchMessages: AppIntent {
                func perform() async throws -> some IntentResult { /* ... */ .result() }
            }
            """#,
            explanation: """
            handler(for:) was a runtime dispatch table mapping intent classes to handler \
            objects. The system now resolves the concrete AppIntent type directly, so the \
            switch disappears. Each case becomes its own struct whose perform() holds what \
            used to live in that handler.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/appintent"
        )),

        // MARK: handle(intent:completion:) → async perform()
        (.handleIntent, MigrationPattern(
            id: "handle-to-async-perform",
            title: "handle(intent:completion:) → async perform()",
            patternType: .delegateMethod,
            beforeCode: #"""
            func handle(intent: INSendMessageIntent,
                        completion: @escaping (INSendMessageIntentResponse) -> Void) {
                MessageService.shared.send(intent.content) { error in
                    let code: INSendMessageIntentResponseCode = (error == nil) ? .success : .failure
                    completion(INSendMessageIntentResponse(code: code, userActivity: nil))
                }
            }
            """#,
            afterCode: #"""
            func perform() async throws -> some IntentResult & ProvidesDialog {
                try await MessageService.shared.send(message, to: recipient)
                return .result(dialog: "Message sent.")
            }
            """#,
            explanation: """
            The completion handler and its response-code enum are replaced by async/await. \
            Success is the normal return; failure is a thrown error, so there is no \
            .failure code to construct. Return .result() for a silent result, or compose \
            with ProvidesDialog to speak or display a confirmation. Response classes \
            generated from a .intentdefinition file are deleted along with it.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/intentresult"
        )),

        // MARK: confirm(intent:) → requestConfirmation
        (.confirmIntent, MigrationPattern(
            id: "confirm-to-request-confirmation",
            title: "confirm(intent:completion:) → requestConfirmation(result:)",
            patternType: .delegateMethod,
            beforeCode: #"""
            func confirm(intent: INSendPaymentIntent,
                         completion: @escaping (INSendPaymentIntentResponse) -> Void) {
                completion(INSendPaymentIntentResponse(code: .ready, userActivity: nil))
            }
            """#,
            afterCode: #"""
            func perform() async throws -> some IntentResult & ProvidesDialog {
                try await requestConfirmation(
                    result: .result(dialog: "Send \(amount.formatted()) to \(recipient)?")
                )
                try await PaymentService.shared.send(amount, to: recipient)
                return .result(dialog: "Payment sent.")
            }
            """#,
            explanation: """
            SiriKit split every interaction into a separate confirm phase and handle phase. \
            App Intents keeps one linear flow: call requestConfirmation inside perform() at \
            the point the user must approve, and continue when it returns. If the user \
            declines, the call throws and perform() unwinds.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/intentdialog"
        )),

        // MARK: resolve…(for:) → @Parameter
        (.resolveMethod, MigrationPattern(
            id: "resolve-to-parameter",
            title: "resolve…(for:with:) → @Parameter declaration",
            patternType: .delegateMethod,
            beforeCode: #"""
            func resolveRecipients(
                for intent: INSendMessageIntent,
                with completion: @escaping ([INSendMessageRecipientResolutionResult]) -> Void
            ) {
                guard let recipients = intent.recipients, !recipients.isEmpty else {
                    completion([.needsValue()])
                    return
                }
                completion(recipients.map { .success(with: $0) })
            }
            """#,
            afterCode: #"""
            @Parameter(title: "Recipient", requestValueDialog: "Who should I message?")
            var recipient: ContactEntity

            func perform() async throws -> some IntentResult {
                // `recipient` is already resolved before perform() runs.
                try await MessageService.shared.send(message, to: recipient)
                return .result()
            }
            """#,
            explanation: """
            Each resolve… callback becomes a declared @Parameter. The framework performs \
            resolution before perform() is called, so a non-optional parameter is \
            guaranteed to have a value. needsValue() becomes the requestValueDialog on the \
            parameter; custom types are modelled as AppEntity (with an EntityQuery) or \
            AppEnum instead of being resolved by hand.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/intentparameter"
        )),

        // MARK: INIntentResolutionResult → async parameter APIs
        (.resolutionResult, MigrationPattern(
            id: "resolutionresult-to-async",
            title: "INIntentResolutionResult → async parameter resolution",
            patternType: .inIntent,
            beforeCode: #"""
            completion(INStringResolutionResult.needsValue())
            completion(INStringResolutionResult.disambiguation(with: ["Small", "Large"]))
            completion(INStringResolutionResult.confirmationRequired(with: "Large"))
            completion(INStringResolutionResult.success(with: size))
            """#,
            afterCode: #"""
            @Parameter(title: "Size", requestValueDialog: "What size?") var size: SizeEntity

            func perform() async throws -> some IntentResult {
                // Disambiguate mid-flight when the choice depends on runtime state:
                let choice = try await $size.requestDisambiguation(
                    among: SizeEntity.available,
                    dialog: "Which size?"
                )
                // Confirm a value you inferred:
                try await $size.requestConfirmation(for: choice, dialog: "Large, correct?")
                return .result()
            }
            """#,
            explanation: """
            The whole INIntentResolutionResult family collapses into the parameter's \
            projected value ($parameter). needsValue() becomes requestValueDialog, \
            disambiguation(with:) becomes requestDisambiguation(among:dialog:), and \
            confirmationRequired(with:) becomes requestConfirmation(for:dialog:). \
            success(with:) has no analogue — a resolved parameter is simply usable.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/intentparameter"
        )),

        // MARK: application(_:handlerFor:) → in-process execution
        (.applicationHandlerFor, MigrationPattern(
            id: "app-handler-to-extension",
            title: "application(_:handlerFor:) → in-app execution",
            patternType: .delegateMethod,
            beforeCode: #"""
            func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
                return SendMessageHandler()
            }
            """#,
            afterCode: #"""
            // Nothing to wire up: an AppIntent in your app target already runs in your
            // app's process, with access to its state.
            //
            // Only if you need out-of-process execution:
            struct MyIntentsExtension: AppIntentsExtension {}
            """#,
            explanation: """
            This delegate method existed so SiriKit could run an intent inside the app \
            rather than the extension. App Intents defined in the app target already \
            execute there, so the hook is obsolete and should be deleted. Reach for \
            AppIntentsExtension only when background execution without launching the app \
            is a requirement.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/app-extension"
        )),

        // MARK: didFinishLaunching → perform()
        (.appLaunchDelegate, MigrationPattern(
            id: "didfinishlaunching-to-perform",
            title: "didFinishLaunching SiriKit setup → perform() / AppShortcutsProvider",
            patternType: .delegateMethod,
            beforeCode: #"""
            func application(
                _ application: UIApplication,
                didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
            ) -> Bool {
                INPreferences.requestSiriAuthorization { _ in }
                updateVocabulary()
                donateRecentIntents()
                return true
            }
            """#,
            afterCode: #"""
            // Shortcuts are declared, not registered at launch:
            struct MyAppShortcuts: AppShortcutsProvider {
                static var appShortcuts: [AppShortcut] {
                    AppShortcut(intent: SendMessage(),
                                phrases: ["Send a message with \(.applicationName)"],
                                shortTitle: "Send Message",
                                systemImageName: "message")
                }
            }

            // Work an intent needs happens inside the intent:
            struct SendMessage: AppIntent {
                func perform() async throws -> some IntentResult {
                    try await MessageService.shared.send(message, to: recipient)
                    return .result()
                }
            }
            """#,
            explanation: """
            Launch-time SiriKit setup assumed the app had to be running to be useful to \
            Siri. App Intents can execute without launching your UI, so anything you did \
            in didFinishLaunching to support Siri must move: shortcut registration becomes \
            a static AppShortcutsProvider, and per-invocation work moves into perform(). \
            Note that perform() may run without your app delegate having run at all — do \
            not rely on launch-time side effects.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/appshortcutsprovider"
        )),

        // MARK: NSUserActivity continuation → OpenIntent
        (.userActivityContinuation, MigrationPattern(
            id: "useractivity-to-openintent",
            title: "application(_:continue:restorationHandler:) → OpenIntent",
            patternType: .delegateMethod,
            beforeCode: #"""
            func application(
                _ application: UIApplication,
                continue userActivity: NSUserActivity,
                restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
            ) -> Bool {
                if let intent = userActivity.interaction?.intent as? INSendMessageIntent {
                    route(to: intent.conversationIdentifier)
                    return true
                }
                return false
            }
            """#,
            afterCode: #"""
            struct OpenConversation: AppIntent, OpenIntent {
                static let title: LocalizedStringResource = "Open Conversation"
                static let openAppWhenRun = true

                @Parameter(title: "Conversation") var target: ConversationEntity

                func perform() async throws -> some IntentResult {
                    Navigator.shared.open(target)
                    return .result()
                }
            }
            """#,
            explanation: """
            Routing an incoming NSUserActivity by inspecting its interaction is replaced by \
            a typed intent. Adopt OpenIntent for "take me to this thing" navigation and set \
            openAppWhenRun so the system brings your app forward. The parameter arrives \
            already resolved to your entity, so identifier parsing goes away.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/openintent"
        )),

        // MARK: Custom INIntent subclass → AppIntent
        (.customIntentSubclass, MigrationPattern(
            id: "inintent-to-appintent",
            title: "INIntent subclass → AppIntent struct",
            patternType: .inIntent,
            beforeCode: #"""
            // Generated from Intents.intentdefinition — do not edit
            public class OrderCoffeeIntent: INIntent {
                @NSManaged public var size: String?
                @NSManaged public var quantity: NSNumber?
            }
            """#,
            afterCode: #"""
            struct OrderCoffee: AppIntent {
                static let title: LocalizedStringResource = "Order Coffee"
                static let description = IntentDescription("Places a coffee order.")

                @Parameter(title: "Size") var size: CoffeeSize          // an AppEnum
                @Parameter(title: "Quantity", default: 1) var quantity: Int

                func perform() async throws -> some IntentResult & ProvidesDialog {
                    try await CoffeeShop.order(size: size, quantity: quantity)
                    return .result(dialog: "Ordering \(quantity) \(size.rawValue) coffee.")
                }
            }
            """#,
            explanation: """
            Custom intents were code-generated from a .intentdefinition file, which forced \
            @NSManaged optionals and stringly-typed values. In App Intents the Swift type \
            is the source of truth: parameters are strongly typed and non-optional when \
            required, enumerations become AppEnum, and model objects become AppEntity. \
            Delete the .intentdefinition file and its generated classes after migrating.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/sirikit/soup-chef-with-app-intents-migrating-custom-intents"
        )),

        // MARK: IN…IntentHandling → AppIntent
        (.intentHandlingProtocol, MigrationPattern(
            id: "intenthandling-to-appintent",
            title: "IN…IntentHandling conformance → AppIntent conformance",
            patternType: .inIntent,
            beforeCode: #"""
            class SendMessageHandler: NSObject, INSendMessageIntentHandling {
                func handle(intent: INSendMessageIntent,
                            completion: @escaping (INSendMessageIntentResponse) -> Void) { /* ... */ }
                func resolveRecipients(for intent: INSendMessageIntent,
                                       with completion: @escaping (...) -> Void) { /* ... */ }
            }
            """#,
            afterCode: #"""
            struct SendMessage: AppIntent {
                static let title: LocalizedStringResource = "Send Message"

                @Parameter(title: "Recipient") var recipient: ContactEntity
                @Parameter(title: "Message") var message: String

                func perform() async throws -> some IntentResult {
                    try await MessageService.shared.send(message, to: recipient)
                    return .result()
                }
            }
            """#,
            explanation: """
            The system-defined handling protocols (INSendMessageIntentHandling and friends) \
            are replaced by a single AppIntent conformance on a value type — no NSObject \
            base class and no separate handler instance. The protocol's resolve/confirm/ \
            handle triple becomes parameters plus one perform(). If you were adopting a \
            system domain, check whether an App Intents schema now covers it, which keeps \
            you eligible for the matching system experiences.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/app-intents"
        )),

        (.intentTypeReference, MigrationPattern(
            id: "intent-type-reference",
            title: "IN…Intent type reference → App Intents equivalent",
            patternType: .inIntent,
            beforeCode: #"""
            let intent = INSendMessageIntent()
            intent.content = text
            """#,
            afterCode: #"""
            var intent = SendMessage()
            intent.message = text
            """#,
            explanation: """
            A reference to a system intent type. Replace it with the AppIntent you defined \
            for the same operation. Where SiriKit used one intent class with many optional \
            properties, prefer several small intents with required parameters — the system \
            can then describe each one precisely to the user.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/app-intents"
        )),

        // MARK: import Intents → import AppIntents
        (.intentsImport, MigrationPattern(
            id: "import-intents-to-appintents",
            title: "import Intents / IntentsUI → import AppIntents",
            patternType: .otherSiriKit,
            beforeCode: #"""
            import Intents
            import IntentsUI
            """#,
            afterCode: #"""
            import AppIntents
            """#,
            explanation: """
            AppIntents replaces both modules. IntentsUI has no counterpart at all: its \
            view controllers existed so users could add shortcuts manually, which App \
            Shortcuts makes unnecessary. Keep importing Intents only while unmigrated \
            SiriKit code still compiles against it.
            """,
            complexity: .autoPatchable,
            appleDocLink: "https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework"
        )),

        // MARK: INInteraction donation → IntentDonationManager
        (.interactionDonation, MigrationPattern(
            id: "ininteraction-to-donate",
            title: "INInteraction donation → IntentDonationManager",
            patternType: .otherSiriKit,
            beforeCode: #"""
            let intent = INSendMessageIntent()
            intent.suggestedInvocationPhrase = "Send a message"

            let interaction = INInteraction(intent: intent, response: nil)
            interaction.donate { error in
                if let error { print(error) }
            }
            """#,
            afterCode: #"""
            var intent = SendMessage()
            intent.recipient = recipient

            try await IntentDonationManager.shared.donate(intent: intent)
            """#,
            explanation: """
            INInteraction wrapped an intent with a response and a completion handler. \
            Donation is now a single async call with the intent itself — there is no \
            interaction object, no response pairing, and no invocation phrase (phrases \
            live on AppShortcut). Donate after the user performs the action so the system \
            can predict it later.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/intentdonationmanager"
        )),

        // MARK: INVoiceShortcutCenter → AppShortcutsProvider
        (.voiceShortcutAPI, MigrationPattern(
            id: "voiceshortcutcenter-to-appshortcuts",
            title: "INVoiceShortcutCenter / INUIAddVoiceShortcutViewController → AppShortcutsProvider",
            patternType: .otherSiriKit,
            beforeCode: #"""
            INVoiceShortcutCenter.shared.getAllVoiceShortcuts { shortcuts, error in
                // inspect what the user recorded
            }

            let shortcut = INShortcut(intent: intent)!
            let controller = INUIAddVoiceShortcutViewController(shortcut: shortcut)
            controller.delegate = self
            present(controller, animated: true)
            """#,
            afterCode: #"""
            struct MyAppShortcuts: AppShortcutsProvider {
                static var appShortcuts: [AppShortcut] {
                    AppShortcut(intent: SendMessage(),
                                phrases: ["Send a message with \(.applicationName)"],
                                shortTitle: "Send Message",
                                systemImageName: "message")
                }
            }
            """#,
            explanation: """
            Users no longer record a phrase per shortcut through a presented view \
            controller. App Shortcuts you declare are available the moment the app is \
            installed, with phrases you supply. Remove the add/edit UI and the code that \
            queried which shortcuts existed; there is no equivalent to \
            getAllVoiceShortcuts because you are no longer waiting on the user to opt in.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/appshortcutsprovider"
        )),

        // MARK: INPreferences → no authorization step
        (.siriAuthorization, MigrationPattern(
            id: "inpreferences-removed",
            title: "INPreferences.requestSiriAuthorization → (removed)",
            patternType: .otherSiriKit,
            beforeCode: #"""
            INPreferences.requestSiriAuthorization { status in
                guard status == .authorized else { return }
                self.enableSiriFeatures()
            }
            """#,
            afterCode: #"""
            // Delete it. App Intents needs no Siri authorization prompt, and there is
            // no INSiriAuthorizationStatus to branch on.
            """#,
            explanation: """
            SiriKit required an explicit user authorization prompt before your app could \
            participate. App Intents has no such gate — your intents are available to Siri, \
            Shortcuts, and Spotlight once shipped. Delete the request, the status checks, \
            and the NSSiriUsageDescription key that accompanied them. Any UI gated on \
            .authorized should now be shown unconditionally.
            """,
            complexity: .autoPatchable,
            appleDocLink: "https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework"
        )),

        // MARK: suggestedInvocationPhrase → @AppShortcutsBuilder
        (.invocationPhrase, MigrationPattern(
            id: "invocationphrase-to-appshortcutsbuilder",
            title: "suggestedInvocationPhrase → @AppShortcutsBuilder phrases",
            patternType: .otherSiriKit,
            beforeCode: #"""
            intent.suggestedInvocationPhrase = "Order coffee"
            activity.suggestedInvocationPhrase = "Order coffee"
            """#,
            afterCode: #"""
            struct CoffeeShortcuts: AppShortcutsProvider {
                @AppShortcutsBuilder
                static var appShortcuts: [AppShortcut] {
                    AppShortcut(intent: OrderCoffee(),
                                phrases: [
                                    "Order coffee with \(.applicationName)",
                                    "Get me a coffee in \(.applicationName)"
                                ],
                                shortTitle: "Order Coffee",
                                systemImageName: "cup.and.saucer")
                }
            }
            """#,
            explanation: """
            A per-donation phrase suggestion becomes a fixed list of phrases on the \
            AppShortcut, built with @AppShortcutsBuilder. Every phrase must contain \
            \\(.applicationName) so Siri can attribute it to your app — a phrase without \
            it will not be matched. Supply several natural phrasings rather than one.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/appshortcutsbuilder"
        )),

        // MARK: isEligibleForPrediction → donations
        (.predictionEligibility, MigrationPattern(
            id: "prediction-to-donation",
            title: "NSUserActivity prediction flags → intent donations",
            patternType: .otherSiriKit,
            beforeCode: #"""
            let activity = NSUserActivity(activityType: "com.example.order")
            activity.isEligibleForPrediction = true
            activity.isEligibleForSearch = true
            activity.suggestedInvocationPhrase = "Order coffee"
            """#,
            afterCode: #"""
            try await IntentDonationManager.shared.donate(intent: OrderCoffee())
            """#,
            explanation: """
            NSUserActivity prediction flags were how you told the system an activity was \
            worth suggesting. Donating the intent now carries that signal, with the \
            advantage that the system knows the parameters involved. Keep NSUserActivity \
            only for state restoration and Handoff; drop the prediction flags.
            """,
            complexity: .autoPatchable,
            appleDocLink: "https://developer.apple.com/documentation/appintents/donations-and-discovery"
        )),

        // MARK: Info.plist intent lists → Swift declarations
        (.infoPlistIntents, MigrationPattern(
            id: "infoplist-to-swift-declarations",
            title: "IntentsSupported / IntentsRestrictedWhileLocked → Swift declarations",
            patternType: .otherSiriKit,
            beforeCode: #"""
            <!-- Intents extension Info.plist -->
            <key>IntentsSupported</key>
            <array><string>INSendMessageIntent</string></array>
            <key>IntentsRestrictedWhileLocked</key>
            <array><string>INSendPaymentIntent</string></array>
            """#,
            afterCode: #"""
            struct SendPayment: AppIntent {
                static let title: LocalizedStringResource = "Send Payment"

                // Replaces IntentsRestrictedWhileLocked:
                static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

                // Replaces IntentsSupported (visibility is declared, not listed):
                static let isDiscoverable = true

                func perform() async throws -> some IntentResult { .result() }
            }
            """#,
            explanation: """
            Supported intents are no longer enumerated in a plist — the compiler emits that \
            metadata from your AppIntent types. Lock-screen restrictions move onto the \
            intent as authenticationPolicy, and isDiscoverable controls whether an intent \
            is offered in Shortcuts and Spotlight. Delete both plist arrays once the \
            extension is gone.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/intentauthenticationpolicy"
        )),

        // MARK: Tracking / privacy → privacy manifest
        (.trackingAuthorization, MigrationPattern(
            id: "privacy-manifest",
            title: "App tracking / privacy usage → PrivacyInfo.xcprivacy declarations",
            patternType: .otherSiriKit,
            beforeCode: #"""
            import AppTrackingTransparency

            ATTrackingManager.requestTrackingAuthorization { status in
                Analytics.enabled = (status == .authorized)
            }

            <!-- Info.plist -->
            <key>NSUserTrackingUsageDescription</key>
            <string>We use this to personalise suggestions.</string>
            """#,
            afterCode: #"""
            // Keep the ATT prompt, and additionally declare the behaviour in a privacy
            // manifest — PrivacyInfo.xcprivacy — in the app and each bundled SDK:
            //
            //   NSPrivacyTracking            <true/>
            //   NSPrivacyTrackingDomains     [ "analytics.example.com" ]
            //   NSPrivacyCollectedDataTypes  [ ... what you collect and why ... ]
            //   NSPrivacyAccessedAPITypes    [ ... required-reason APIs ... ]
            """#,
            explanation: """
            The tracking prompt itself has not changed, but the declaration has: data \
            collection and required-reason API use must be described in a PrivacyInfo. \
            xcprivacy manifest, which Apple aggregates into your privacy report at \
            submission. This matters during an App Intents migration because intents \
            expose your data to Siri and Spotlight — anything you surface there needs to \
            be covered by these declarations.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/bundleresources/privacy-manifest-files"
        )),

        // MARK: Catch-all
        (.intentsFrameworkType, MigrationPattern(
            id: "generic-sirikit-type",
            title: "Intents framework type → App Intents equivalent",
            patternType: .otherSiriKit,
            beforeCode: #"""
            // Some remaining Intents-framework symbol, e.g.
            let vocabulary = INVocabulary.shared()
            vocabulary.setVocabularyStrings(names, of: .contactName)
            """#,
            afterCode: #"""
            // Model the data as entities the system can query directly:
            struct ContactEntity: AppEntity {
                static let typeDisplayRepresentation: TypeDisplayRepresentation = "Contact"
                static let defaultQuery = ContactQuery()

                let id: String
                var displayRepresentation: DisplayRepresentation { "\(name)" }
                let name: String
            }
            """#,
            explanation: """
            A SiriKit symbol with no direct one-to-one replacement. The general move is \
            from imperative registration (handing the system strings and vocabulary) to \
            declarative modelling: expose your data as AppEntity types with an EntityQuery, \
            and the system resolves names against them itself. Check this occurrence \
            individually against the App Intents documentation.
            """,
            complexity: .manualReview,
            appleDocLink: "https://developer.apple.com/documentation/appintents/app-entities"
        )),
    ]
}
