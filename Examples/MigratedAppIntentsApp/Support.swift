import Foundation

/// Minimal stand-ins so this example compiles on its own.
enum MessageService {
    static func send(_ message: String, to recipient: String) async throws {}
}

enum CoffeeShop {
    static func order(size: CoffeeSize, quantity: Int) async throws {}
}
