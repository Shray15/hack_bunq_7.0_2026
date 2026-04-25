import SwiftUI

/// Read-only list of all paid orders. Reached from ProfileView. In sandbox
/// this is dominated by meal-card orders, but bunq.me orders the user
/// manually marked paid show up here too.
struct OrderHistoryView: View {
    @State private var orders: [Order] = []
    @State private var isLoading: Bool = false
    @State private var errorMsg: String?

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .navigationTitle("Order history")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && orders.isEmpty {
            ProgressView().controlSize(.large)
        } else if let errorMsg, orders.isEmpty {
            errorState(message: errorMsg)
        } else if orders.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(orders) { order in
                    OrderHistoryRow(order: order)
                }
            }
            .appScrollContentPadding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppTheme.primary.opacity(0.6))
            Text("No paid orders yet.")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text("Pay for a grocery order to see it here. Sandbox demo: meal-card payments and manually-confirmed bunq.me payments both land in this list.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text("Could not load history")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button("Try again") {
                Task { await load() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.primary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        do {
            orders = try await APIService.shared.getPaidOrders(limit: 100)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

private struct OrderHistoryRow: View {
    let order: Order

    var body: some View {
        AppCard(padding: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: order.paidViaMealCard ? "creditcard.and.123" : "creditcard.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(order.paidViaMealCard ? AppTheme.primary : AppTheme.success)
                    .frame(width: 42, height: 42)
                    .background(
                        (order.paidViaMealCard ? AppTheme.primary : AppTheme.success).opacity(0.14)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(order.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        AppTag(StoreCatalog.displayName(for: order.store), color: AppTheme.primary)
                        AppTag(order.paymentMethodLabel, color: order.paidViaMealCard ? AppTheme.primary : AppTheme.success, icon: "creditcard")
                    }
                    if let paidAt = order.paidAt {
                        Text(paidAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Spacer(minLength: 6)

                Text("€\(String(format: "%.2f", order.totalEur))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .monospacedDigit()
            }
        }
    }
}
