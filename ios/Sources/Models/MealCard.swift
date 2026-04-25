import Foundation

// MARK: - Wire shapes (match backend `/meal-card` contract)

/// Monthly bunq meal card. Backed by a real bunq sandbox sub-account
/// (MonetaryAccountBank) plus a virtual debit card (CardDebit type=VIRTUAL).
/// One per (user, month).
struct MealCard: Codable, Identifiable, Hashable {
    let id: String
    let monthYear: String           // "YYYY-MM"
    let monthlyBudgetEur: Double
    let currentBalanceEur: Double
    let last4: String?
    let iban: String
    let status: String              // "active" | "expired" | "cancelled"
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case monthYear         = "month_year"
        case monthlyBudgetEur  = "monthly_budget_eur"
        case currentBalanceEur = "current_balance_eur"
        case last4             = "last_4"
        case iban
        case status
        case expiresAt         = "expires_at"
        case createdAt         = "created_at"
    }

    var isActive: Bool { status == "active" }

    var spentEur: Double { max(0, monthlyBudgetEur - currentBalanceEur) }

    /// 0...1 — fraction of the budget that has been spent.
    var spentRatio: Double {
        guard monthlyBudgetEur > 0 else { return 0 }
        return min(spentEur / monthlyBudgetEur, 1)
    }

    /// "2026-04" → "April 2026".
    var displayMonth: String {
        let parts = monthYear.split(separator: "-").map(String.init)
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return monthYear }
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let date = Calendar.current.date(from: components) else { return monthYear }
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// "2026-04" → "April".
    var displayMonthShort: String {
        let parts = monthYear.split(separator: "-").map(String.init)
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return monthYear }
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let date = Calendar.current.date(from: components) else { return monthYear }
        return date.formatted(.dateTime.month(.wide))
    }

    /// "•••• 1234" — null-safe for the case where bunq sandbox didn't issue
    /// a CardDebit (we still show the card visually, just without digits).
    var maskedCardNumber: String {
        "•••• " + (last4 ?? "0000")
    }

    /// "NL12 BUNQ 0123 4567 89" — readable IBAN with spaces every 4 chars.
    var formattedIban: String {
        let stripped = iban.replacingOccurrences(of: " ", with: "")
        var out = ""
        for (i, ch) in stripped.enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }
}

/// One row in the bunq sub-account transaction log. Sign convention:
/// negative `amountEur` = a charge (money leaving the meal card),
/// positive = a top-up (money added).
struct MealCardTransaction: Codable, Identifiable, Hashable {
    let id: String
    let amountEur: Double
    let description: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case amountEur   = "amount_eur"
        case description
        case createdAt   = "created_at"
    }

    var isCharge: Bool { amountEur < 0 }

    /// "−€12.34" / "+€50.00".
    var formattedAmount: String {
        let abs = abs(amountEur)
        let formatted = String(format: "%.2f", abs)
        return isCharge ? "−€\(formatted)" : "+€\(formatted)"
    }
}

/// `payment_method` discriminator on `POST /order/checkout`. Default flow
/// is bunq.me (existing); meal-card pays from the user's virtual sub-account.
enum CheckoutPaymentMethod: String, Codable {
    case bunqMe   = "bunq_me"
    case mealCard = "meal_card"
}
