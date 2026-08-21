import AppIntents

/// Replaces the `.intentdefinition`-generated `OrderCoffeeIntent: INIntent`.
/// `@NSManaged var size: String?` becomes a typed, non-optional parameter.
enum CoffeeSize: String, AppEnum {
    case small, medium, large

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Coffee Size"
    static let caseDisplayRepresentations: [CoffeeSize: DisplayRepresentation] = [
        .small: "Small", .medium: "Medium", .large: "Large",
    ]
}

struct OrderCoffee: AppIntent {
    static let title: LocalizedStringResource = "Order Coffee"
    static let description = IntentDescription("Places a coffee order.")

    @Parameter(title: "Size") var size: CoffeeSize
    @Parameter(title: "Quantity", default: 1) var quantity: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await CoffeeShop.order(size: size, quantity: quantity)
        return .result(dialog: "Ordering \(quantity) \(size.rawValue) coffee.")
    }
}
