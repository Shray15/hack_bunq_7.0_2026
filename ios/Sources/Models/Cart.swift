import Foundation

// MARK: - Wire shapes (match backend contracts)

/// Cart item as returned by `POST /cart/{cart_id}/select-store`.
struct CartItem: Identifiable, Codable, Hashable {
    /// Backend uses `product_id` as the catalogue ID; we expose it as the row id too.
    let productId: String
    let ingredient: String
    let productName: String
    let imageURL: URL?
    let qty: Double
    let unit: String?
    let priceEur: Double

    var id: String { productId }

    enum CodingKeys: String, CodingKey {
        case productId   = "product_id"
        case ingredient
        case productName = "name"
        case imageURL    = "image_url"
        case qty
        case unit
        case priceEur    = "price_eur"
    }
}

/// One row in the per-store comparison returned by `POST /cart/from-recipe`.
struct StoreComparison: Identifiable, Codable, Hashable {
    let store: String
    let totalEur: Double
    let itemCount: Int
    let missingCount: Int

    var id: String { store }

    enum CodingKeys: String, CodingKey {
        case store
        case totalEur     = "total_eur"
        case itemCount    = "item_count"
        case missingCount = "missing_count"
    }
}

/// Response of `POST /cart/from-recipe` — totals only, no items yet.
struct CartComparisonResponse: Codable, Hashable {
    let cartId: String
    let recipeId: String
    let comparison: [StoreComparison]

    enum CodingKeys: String, CodingKey {
        case cartId    = "cart_id"
        case recipeId  = "recipe_id"
        case comparison
    }
}

/// Response of `POST /cart/{cart_id}/select-store` — the items list.
struct CartItemsResponse: Codable, Hashable {
    let cartId: String
    let selectedStore: String
    let totalEur: Double
    let items: [CartItem]

    enum CodingKeys: String, CodingKey {
        case cartId        = "cart_id"
        case selectedStore = "selected_store"
        case totalEur      = "total_eur"
        case items
    }
}

/// Response of `POST /order/checkout`.
struct CheckoutResponse: Codable {
    let orderId: String?
    let paymentURL: String
    let amountEur: Double

    enum CodingKeys: String, CodingKey {
        case orderId    = "order_id"
        case paymentURL = "payment_url"
        case amountEur  = "amount_eur"
    }
}

// MARK: - Store catalog helpers

enum StoreCatalog {
    static func displayName(for store: String) -> String {
        switch store.lowercased() {
        case "ah":     return "Albert Heijn"
        case "picnic": return "Picnic"
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
