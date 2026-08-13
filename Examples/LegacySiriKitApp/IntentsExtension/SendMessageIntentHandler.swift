import Intents

final class SendMessageIntentHandler: NSObject, INSendMessageIntentHandling {

    func resolveRecipients(
        for intent: INSendMessageIntent,
        with completion: @escaping ([INSendMessageRecipientResolutionResult]) -> Void
    ) {
        guard let recipients = intent.recipients, !recipients.isEmpty else {
            completion([INSendMessageRecipientResolutionResult.needsValue()])
            return
        }
        completion(recipients.map { .success(with: $0) })
    }

    func resolveContent(
        for intent: INSendMessageIntent,
        with completion: @escaping (INStringResolutionResult) -> Void
    ) {
        guard let content = intent.content, !content.isEmpty else {
            completion(INStringResolutionResult.needsValue())
            return
        }
        completion(INStringResolutionResult.success(with: content))
    }

    func confirm(intent: INSendMessageIntent, completion: @escaping (INSendMessageIntentResponse) -> Void) {
        completion(INSendMessageIntentResponse(code: .ready, userActivity: nil))
    }

    func handle(intent: INSendMessageIntent, completion: @escaping (INSendMessageIntentResponse) -> Void) {
        MessageService.shared.send(intent.content ?? "") { error in
            let code: INSendMessageIntentResponseCode = error == nil ? .success : .failure
            completion(INSendMessageIntentResponse(code: code, userActivity: nil))
        }
    }
}

final class SearchMessagesIntentHandler: NSObject, INSearchForMessagesIntentHandling {
    func handle(intent: INSearchForMessagesIntent, completion: @escaping (INSearchForMessagesIntentResponse) -> Void) {
        completion(INSearchForMessagesIntentResponse(code: .success, userActivity: nil))
    }
}
