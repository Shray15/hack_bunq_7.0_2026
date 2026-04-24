import Foundation

struct CartItem: Identifiable, Codable {
    let id: String          // maps to product_id in JSON
    let ingredient: String
    let productName: String
    let priceEur: Double
    let qty: Int
    let store: String

    enum CodingKeys: String, CodingKey {
        case id          = "product_id"
        case ingredient
        case productName = "name"
        case priceEur    = "price_eur"
        case qty, store
    }
}

struct CartResponse: Codable {
    let items: [CartItem]
    let totalEur: Double
    let store: String

    enum CodingKeys: String, CodingKey {
        case items
        case totalEur = "total_eur"
        case store
    }
}

struct CheckoutResponse: Codable {
    let paymentURL: String
    let amountEur: Double

    enum CodingKeys: String, CodingKey {
        case paymentURL = "payment_url"
        case amountEur  = "amount_eur"
    }
}
