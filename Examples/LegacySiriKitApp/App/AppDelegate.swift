import UIKit
import Intents

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        INPreferences.requestSiriAuthorization { status in
            guard status == .authorized else { return }
            ShortcutDonations.shared.donateRecent()
        }
        updateVocabulary()
        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard let intent = userActivity.interaction?.intent as? INSendMessageIntent else { return false }
        Navigator.shared.openConversation(intent.conversationIdentifier)
        return true
    }

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        guard intent is INSendMessageIntent else { return nil }
        return SendMessageIntentHandler()
    }

    private func updateVocabulary() {
        let names = ContactStore.shared.allNames()
        INVocabulary.shared().setVocabularyStrings(NSOrderedSet(array: names), of: .contactName)
    }
}
