import UIKit
import Intents
import IntentsUI

/// Lets the user record a phrase for a shortcut — UI that App Intents removes entirely.
final class AddShortcutViewController: UIViewController, INUIAddVoiceShortcutViewControllerDelegate {

    func presentAddShortcut() {
        let intent = INSendMessageIntent()
        intent.suggestedInvocationPhrase = "Send a message"

        guard let shortcut = INShortcut(intent: intent) else { return }
        let controller = INUIAddVoiceShortcutViewController(shortcut: shortcut)
        controller.delegate = self
        present(controller, animated: true)
    }

    func addVoiceShortcutViewController(
        _ controller: INUIAddVoiceShortcutViewController,
        didFinishWith voiceShortcut: INVoiceShortcut?,
        error: Error?
    ) {
        controller.dismiss(animated: true)
    }

    func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
        controller.dismiss(animated: true)
    }
}
