import Foundation

struct CartItem: Identifiable, Codable, Hashable {
    let id: String
    let ingredientName: String
    let store: String
    let productId: String
    let productName: String
    let qty: Double
    let unitPriceEur: Double
    let totalPriceEur: Double
    let imageURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case ingredientName  = "ingredient_name"
        case store
        case productId       = "product_id"
        case productName     = "product_name"
        case qty
        case unitPriceEur    = "unit_price_eur"
        case totalPriceEur   = "total_price_eur"
        case imageURL        = "image_url"
    }
}

struct StoreComparison: Identifiable, Codable, Hashable {
    let store: String
    let totalEur: Double
    let missing: [String]
    let itemCount: Int

    var id: String { store }

    enum CodingKeys: String, CodingKey {
        case store
        case totalEur  = "total_eur"
        case missing
        case itemCount = "item_count"
    }
}

struct CartResponse: Codable {
    let id: String
    let recipeId: String?
    let status: String
    let selectedStore: String?
    let comparison: [StoreComparison]
    let items: [CartItem]

    enum CodingKeys: String, CodingKey {
        case id
        case recipeId       = "recipe_id"
        case status
        case selectedStore  = "selected_store"
        case comparison
        case items
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

extension CartResponse {
    var totalEur: Double {
        items.reduce(0) { $0 + $1.totalPriceEur }
    }
}

enum StoreCatalog {
    static func displayName(for store: String) -> String {
        switch store.lowercased() {
        case "ah":     return "Albert Heijn"
        case "picnic": return "Picnic"
        case "jumbo":  return "Jumbo"
        default:       return store.capitalized
        }
    }

    static func accentColor(for store: String) -> String {
        switch store.lowercased() {
        case "ah":     return "ahBlue"
        case "picnic": return "picnicRed"
        default:       return "default"
        }
    }
}
