import SwiftUI

/// Two-option picker rendered above the Pay button on the order-review screen.
/// The meal-card option is disabled when the user has no card yet or when the
/// current balance can't cover the cart total.
struct PaymentMethodPicker: View {
    @Binding var selected: CheckoutPaymentMethod
    let amount: Double
    let mealCard: MealCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("How will you pay?", eyebrow: "Payment")

            VStack(spacing: 10) {
                option(
                    method: .bunqMe,
                    title: "Bunq.me",
                    subtitle: "Open bunq, confirm via iDEAL, card, or bank.",
                    icon: "creditcard"
                )
                option(
                    method: .mealCard,
                    title: mealCardTitle,
                    subtitle: mealCardSubtitle,
                    icon: "creditcard.and.123",
                    disabled: !mealCardSufficient,
                    disabledReason: mealCardDisabledReason
                )
            }
        }
    }

    // MARK: - Option row

    private func option(
        method: CheckoutPaymentMethod,
        title: String,
        subtitle: String,
        icon: String,
        disabled: Bool = false,
        disabledReason: String? = nil
    ) -> some View {
        let isSelected = selected == method && !disabled

        return Button {
            guard !disabled else { return }
            selected = method
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : AppTheme.primary)
                    .frame(width: 38, height: 38)
                    .background(
                        isSelected
                            ? AppTheme.primary
                            : AppTheme.primary.opacity(0.14)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(disabled ? AppTheme.secondaryText : AppTheme.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let disabledReason {
                        Text(disabledReason)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 6)

                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? AppTheme.primary : AppTheme.stroke,
                            lineWidth: isSelected ? 6 : 2
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(AppTheme.primary)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(14)
            .background(isSelected ? AppTheme.primary.opacity(0.06) : AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? AppTheme.primary.opacity(0.5) : AppTheme.stroke,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .opacity(disabled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Meal-card copy

    private var mealCardTitle: String {
        guard let card = mealCard else { return "Meal Card" }
        return "Meal Card · €\(format(card.currentBalanceEur))"
    }

    private var mealCardSubtitle: String {
        guard let card = mealCard else {
            return "Set up a monthly meal card from Home to pay from a dedicated bunq sub-account."
        }
        if card.currentBalanceEur < amount {
            return "Pay groceries directly from your monthly meal card."
        }
        let after = card.currentBalanceEur - amount
        return "After this: €\(format(after)) remaining for the month."
    }

    private var mealCardSufficient: Bool {
        guard let card = mealCard else { return false }
        return card.isActive && card.currentBalanceEur + 0.005 >= amount
    }

    private var mealCardDisabledReason: String? {
        guard let card = mealCard else { return "No card yet" }
        if !card.isActive { return "Card not active" }
        if card.currentBalanceEur + 0.005 < amount { return "Insufficient balance" }
        return nil
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

#if DEBUG
#Preview("Both available") {
    PaymentMethodPicker(
        selected: .constant(.bunqMe),
        amount: 23.40,
        mealCard: MockData.makeMealCard(budgetEur: 300, balanceEur: 240)
    )
    .padding()
    .background(AppTheme.backgroundTop)
}

#Preview("Insufficient balance") {
    PaymentMethodPicker(
        selected: .constant(.bunqMe),
        amount: 23.40,
        mealCard: MockData.makeMealCard(budgetEur: 300, balanceEur: 12)
    )
    .padding()
    .background(AppTheme.backgroundTop)
}

#Preview("No card") {
    PaymentMethodPicker(
        selected: .constant(.bunqMe),
        amount: 23.40,
        mealCard: nil
    )
    .padding()
    .background(AppTheme.backgroundTop)
}
#endif
