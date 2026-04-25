import SwiftUI

/// Compact meal-card tile rendered on the Home screen. Two states:
/// has-card (gradient card with balance + budget progress) and no-card
/// (muted setup CTA). Tap closures are routed by the parent so the tile
/// itself can stay layout-only.
struct MealCardTile: View {
    let card: MealCard?
    let isLoading: Bool
    let onSetup: () -> Void
    let onOpen: () -> Void

    var body: some View {
        if let card {
            Button(action: onOpen) {
                activeTile(card: card)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Meal card \(card.displayMonthShort), €\(amountString(card.currentBalanceEur)) of €\(amountString(card.monthlyBudgetEur)) remaining"
            )
        } else {
            Button(action: onSetup) {
                setupTile
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set up your monthly meal card")
        }
    }

    // MARK: - Active card tile

    private func activeTile(card: MealCard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text("Meal Card · \(card.displayMonthShort)")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("€\(amountString(card.currentBalanceEur))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("of €\(amountString(card.monthlyBudgetEur))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }

            BudgetProgressBar(spentRatio: card.spentRatio)

            Text(card.maskedCardNumber)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .tracking(2)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [AppTheme.primaryDeep, AppTheme.primary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 140, height: 140)
                .blur(radius: 12)
                .offset(x: 50, y: -60)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.primaryDeep.opacity(0.25), radius: 18, y: 10)
    }

    // MARK: - Empty / setup tile

    private var setupTile: some View {
        AppCard(padding: 16, background: AppTheme.mutedCard) {
            HStack(spacing: 14) {
                Image(systemName: "creditcard.and.123")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.primary.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(isLoading ? "Loading meal card…" : "Set up your meal card")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                    Text("Pay groceries from a dedicated bunq sub-account.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private func amountString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

/// Thin progress bar used by both the tile and the full screen.
struct BudgetProgressBar: View {
    let spentRatio: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: max(geo.size.width * (1 - spentRatio), 6))
            }
        }
        .frame(height: 6)
    }
}

#if DEBUG
#Preview("Active card") {
    let card = MockData.makeMealCard(budgetEur: 300, balanceEur: 230.4)
    return MealCardTile(card: card, isLoading: false, onSetup: {}, onOpen: {})
        .padding()
        .background(AppTheme.backgroundTop)
}

#Preview("No card") {
    MealCardTile(card: nil, isLoading: false, onSetup: {}, onOpen: {})
        .padding()
        .background(AppTheme.backgroundTop)
}
#endif
