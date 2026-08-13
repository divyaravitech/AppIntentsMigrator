import Foundation
import Intents

/// Donates interactions so Siri can predict them, the SiriKit way.
final class ShortcutDonations {
    static let shared = ShortcutDonations()

    func donate(message: String, to recipient: String) {
        let intent = INSendMessageIntent()
        intent.content = message
        intent.suggestedInvocationPhrase = "Send a message"

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error { print("Donation failed: \(error)") }
        }
    }

    func donateRecent() {
        let activity = NSUserActivity(activityType: "com.example.sendMessage")
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = true
        activity.suggestedInvocationPhrase = "Message my team"
        activity.becomeCurrent()
    }

    func existingShortcuts(completion: @escaping ([INVoiceShortcut]) -> Void) {
        INVoiceShortcutCenter.shared.getAllVoiceShortcuts { shortcuts, error in
            if let error { print("Lookup failed: \(error)") }
            completion(shortcuts ?? [])
        }
    }
}
