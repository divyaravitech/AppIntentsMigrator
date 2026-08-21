import AppIntents

/// `IntentHandler: INExtension` + `SendMessageIntentHandler` collapse into this.
struct SendMessage: AppIntent {
    static let title: LocalizedStringResource = "Send Message"
    static let description = IntentDescription("Sends a message to a contact.")

    @Parameter(title: "Recipient", requestValueDialog: "Who should I message?")
    var recipient: String

    @Parameter(title: "Message", requestValueDialog: "What should it say?")
    var message: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MessageService.send(message, to: recipient)
        return .result(dialog: "Message sent.")
    }
}
