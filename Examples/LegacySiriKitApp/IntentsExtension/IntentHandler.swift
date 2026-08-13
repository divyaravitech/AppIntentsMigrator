import Intents

/// Principal class of the Intents extension: routes an intent to a handler object.
class IntentHandler: INExtension {

    override func handler(for intent: INIntent) -> Any? {
        switch intent {
        case is INSendMessageIntent:
            return SendMessageIntentHandler()
        case is INSearchForMessagesIntent:
            return SearchMessagesIntentHandler()
        default:
            return nil
        }
    }
}
