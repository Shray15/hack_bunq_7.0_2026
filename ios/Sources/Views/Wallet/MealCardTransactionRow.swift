import SwiftUI

struct MealCardTransactionRow: View {
    let tx: MealCardTransaction

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconTint)
                .frame(width: 36, height: 36)
                .background(iconTint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.description.isEmpty ? defaultDescription : tx.description)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let when = tx.createdAt {
                    Text(when, style: .relative)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text("Just now")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer()

            Text(tx.formattedAmount)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(amountTint)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
    }

    private var iconName: String {
        tx.isCharge ? "cart.fill" : "arrow.down.circle.fill"
    }

    private var iconTint: Color {
        tx.isCharge ? AppTheme.accent : AppTheme.success
    }

    private var amountTint: Color {
        tx.isCharge ? AppTheme.text : AppTheme.success
    }

    private var defaultDescription: String {
        tx.isCharge ? "Groceries" : "Top-up"
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 8) {
        MealCardTransactionRow(tx: MealCardTransaction(
            id: "1", amountEur: -23.40, description: "Groceries from AH", createdAt: Date()
        ))
        MealCardTransactionRow(tx: MealCardTransaction(
            id: "2", amountEur: 50, description: "Meal card top-up", createdAt: Date().addingTimeInterval(-86400)
        ))
    }
    .padding()
    .background(AppTheme.backgroundTop)
}
#endif
