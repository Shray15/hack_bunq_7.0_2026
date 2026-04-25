import Foundation

// MARK: - Wire shapes (match backend contracts)

/// Cart item as returned by `POST /cart/{cart_id}/select-store`.
struct CartItem: Identifiable, Codable, Hashable {
    /// Backend cart-item UUID. Used as the path component on
    /// `PATCH /cart/{cart_id}/items/{item_id}` and as the SwiftUI row identity
    /// (so a product that exists in both the AH and Picnic carts still has
    /// distinct rows).
    let cartItemId: String
    /// AH/Picnic catalogue product ID — opaque, used only for display debug.
    let productId: String
    let ingredient: String
    let productName: String
    let imageURL: URL?
    let qty: Double
    let unit: String?
    let priceEur: Double

    var id: String { cartItemId }

    enum CodingKeys: String, CodingKey {
        case cartItemId  = "id"
        case productId   = "product_id"
        case ingredient  = "ingredient_name"
        case productName = "product_name"
        case imageURL    = "image_url"
        case qty
        case unit
        case priceEur    = "total_price_eur"
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
///
/// `paymentURL` is nil for the meal-card flow (the card is charged synchronously
/// and the order is already `paid` by the time this response lands), and
/// non-nil for the bunq.me flow.
struct CheckoutResponse: Codable {
    let orderId: String?
    let paymentURL: String?
    let amountEur: Double
    let paymentMethod: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case orderId        = "order_id"
        case paymentURL     = "payment_url"
        case amountEur      = "amount_eur"
        case paymentMethod  = "payment_method"
        case status
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
