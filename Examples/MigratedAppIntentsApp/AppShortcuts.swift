import AppIntents

/// Replaces INVoiceShortcutCenter, INUIAddVoiceShortcutViewController and every
/// `suggestedInvocationPhrase`. Declared once, available as soon as the app installs.
struct ExampleAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendMessage(),
            phrases: ["Send a message with \(.applicationName)"],
            shortTitle: "Send Message",
            systemImageName: "message"
        )
        AppShortcut(
            intent: OrderCoffee(),
            phrases: ["Order coffee with \(.applicationName)"],
            shortTitle: "Order Coffee",
            systemImageName: "cup.and.saucer"
        )
    }
}

/// Replaces `INInteraction(intent:response:).donate { }`.
enum Donations {
    static func donateOrder() async throws {
        try await IntentDonationManager.shared.donate(intent: OrderCoffee())
    }
}
