import Foundation

/// Wire shape for `POST /orders/{order_id}/share-cost` and
/// `GET /orders/{order_id}/share-cost`. The bunq.me URL is fixed-amount per
/// person — friends pay their share via iDEAL/card/bank.
struct MealShare: Codable, Identifiable, Hashable {
    let id: String
    let orderId: String
    let participantCount: Int
    let includeSelf: Bool
    let perPersonEur: Double
    let totalEur: Double
    let shareURL: String
    let bunqRequestId: String?
    let status: String          // "open" | "closed"
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case orderId          = "order_id"
        case participantCount = "participant_count"
        case includeSelf      = "include_self"
        case perPersonEur     = "per_person_eur"
        case totalEur         = "total_eur"
        case shareURL         = "share_url"
        case bunqRequestId    = "bunq_request_id"
        case status
        case createdAt        = "created_at"
    }

    /// Total people the bill is divided across — including the owner if
    /// `includeSelf` is true.
    var divisor: Int { participantCount + (includeSelf ? 1 : 0) }
}
