import Foundation

/// Wire shape for `GET /orders` and `GET /orders/{id}`. `recipeName` is
/// populated by the backend's join when listing history; null elsewhere.
struct Order: Codable, Identifiable, Hashable {
    let id: String
    let cartId: String
    let store: String
    let totalEur: Double
    let paymentMethod: String
    let bunqPaymentURL: String?
    let bunqRequestId: String?
    let bunqPaymentId: String?
    let status: String
    let paidAt: Date?
    let fulfilledAt: Date?
    let createdAt: Date
    let recipeName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case cartId            = "cart_id"
        case store
        case totalEur          = "total_eur"
        case paymentMethod     = "payment_method"
        case bunqPaymentURL    = "bunq_payment_url"
        case bunqRequestId     = "bunq_request_id"
        case bunqPaymentId     = "bunq_payment_id"
        case status
        case paidAt            = "paid_at"
        case fulfilledAt       = "fulfilled_at"
        case createdAt         = "created_at"
        case recipeName        = "recipe_name"
    }

    var displayName: String {
        recipeName ?? "Groceries from \(StoreCatalog.displayName(for: store))"
    }

    var paidViaMealCard: Bool { paymentMethod == "meal_card" }

    var paymentMethodLabel: String {
        paidViaMealCard ? "Meal Card" : "Bunq.me"
    }
}
