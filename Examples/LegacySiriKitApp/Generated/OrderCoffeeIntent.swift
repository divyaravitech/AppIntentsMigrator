// Generated from Intents.intentdefinition — do not edit.
import Intents

@objc(OrderCoffeeIntent)
public class OrderCoffeeIntent: INIntent {
    @NSManaged public var size: String?
    @NSManaged public var quantity: NSNumber?
}

@objc(OrderCoffeeIntentResponse)
public class OrderCoffeeIntentResponse: INIntentResponse {
    @NSManaged public var confirmationCode: String?
}
