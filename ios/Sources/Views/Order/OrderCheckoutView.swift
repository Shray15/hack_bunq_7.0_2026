import UIKit
import SwiftUI

@MainActor
final class OrderViewModel: ObservableObject {
    @Published var paymentURL: URL?
    @Published var orderId: String?
    @Published var isOrdering: Bool = false
    @Published var isPaid: Bool = false
    @Published var errorMsg: String?

    private let api = APIService.shared
    private let realtime = RealtimeService.shared
    private var listenerTask: Task<Void, Never>?

    /// `POST /order/checkout` — mints the bunq.me URL and starts watching for the
    /// matching `order_status: paid` SSE event.
    func checkout(cartId: String) async {
        isOrdering = true
        errorMsg = nil
        defer { isOrdering = false }
        do {
            let response = try await api.checkout(cartId: cartId)
            paymentURL = URL(string: response.paymentURL)
            orderId = response.orderId
            startWaitingForPayment()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    /// User backed out of the bunq flow before the webhook fired.
    func cancel() {
        listenerTask?.cancel()
        listenerTask = nil
        paymentURL = nil
        orderId = nil
        isPaid = false
    }

    /// User says they paid but the SSE event hasn't arrived (e.g. simulator,
    /// flaky webhook). Treat as paid so the demo doesn't stall.
    func markPaidManually() {
        isPaid = true
        listenerTask?.cancel()
        listenerTask = nil
    }

    private func startWaitingForPayment() {
        listenerTask?.cancel()
        let stream = realtime.subscribe()
        listenerTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                guard case .orderStatus(let payload) = event else { continue }
                guard payload.orderId == self.orderId else { continue }
                if payload.status == "paid" {
                    self.isPaid = true
                    return
                }
            }
        }
    }
}

struct OrderCheckoutView: View {
    let recipe: Recipe
    let servings: Int
    let cart: CartItemsResponse
    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = OrderViewModel()
    @State private var excludedItemIDs: Set<String> = []
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            cartContent

            if shouldShowOverlay {
                paymentOverlay
                    .transition(.opacity)
            }
        }
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", action: onClose)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .onChange(of: vm.paymentURL) { _, url in
            if let url {
                UIApplication.shared.open(url)
            }
        }
        .onChange(of: vm.errorMsg) { _, value in
            showError = value != nil
        }
        .onChange(of: vm.isPaid) { _, paid in
            guard paid else { return }
            appState.completeOrder(recipe: recipe, servings: servings)
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                onClose()
            }
        }
        .alert("Something went wrong", isPresented: $showError) {
            Button("OK") { vm.errorMsg = nil }
        } message: {
            Text(vm.errorMsg ?? "")
        }
        .animation(.easeOut(duration: 0.18), value: shouldShowOverlay)
    }

    private var shouldShowOverlay: Bool {
        vm.isOrdering || vm.paymentURL != nil || vm.isPaid
    }

    // MARK: - Cart content

    private var cartContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                basketCard
                totalCard
            }
            .appScrollContentPadding()
        }
        .safeAreaInset(edge: .bottom) {
            payButton
        }
    }

    private var summaryCard: some View {
        AppCard(background: Color(red: 0.90, green: 0.97, blue: 0.93)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    AppTag(StoreCatalog.displayName(for: cart.selectedStore), color: AppTheme.success, icon: "cart.fill")
                    Spacer()
                    Text(itemCountLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Text(recipe.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                Text("Scaled for \(servings) \(servings == 1 ? "person" : "people"). Tap an item to skip anything you already have.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var basketCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                AppSectionHeader("Basket", detail: "Each row is the actual product we'd order at \(StoreCatalog.displayName(for: cart.selectedStore)).")

                ForEach(cart.items) { item in
                    BasketRow(
                        item: item,
                        isIncluded: !excludedItemIDs.contains(item.id)
                    ) {
                        toggle(item.id)
                    }

                    if item.id != cart.items.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var totalCard: some View {
        AppCard(background: AppTheme.mutedCard) {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("€\(filteredTotal, specifier: "%.2f")")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.primaryDeep)
                        if hasExclusions {
                            Text("€\(cart.totalEur, specifier: "%.2f") before skips")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                                .strikethrough(true, color: AppTheme.secondaryText)
                        }
                    }
                }

                HStack {
                    AppTag("Pay via bunq", color: AppTheme.success, icon: "creditcard.fill")
                    Spacer()
                    Text("bunq.me opens after checkout")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private var payButton: some View {
        Button {
            Task { await vm.checkout(cartId: cart.cartId) }
        } label: {
            Group {
                if vm.isOrdering {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else if !hasIncludedItems {
                    Label("Add an item to checkout", systemImage: "cart.badge.minus")
                } else {
                    Label("Pay €\(filteredTotal, specifier: "%.2f") via bunq", systemImage: "creditcard.fill")
                }
            }
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.success))
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .disabled(vm.isOrdering || !hasIncludedItems)
    }

    // MARK: - Payment overlay

    private var paymentOverlay: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { /* swallow */ }

            AppCard {
                VStack(spacing: 16) {
                    if vm.isPaid {
                        paidContent
                    } else {
                        waitingContent
                    }
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 32)
        }
    }

    private var waitingContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.success.opacity(0.14))
                    .frame(width: 70, height: 70)
                Image(systemName: "creditcard.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.success)
            }

            Text("Confirm in bunq")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.text)
            Text("We'll mark this paid the moment bunq confirms — usually a few seconds.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)

            ProgressView()
                .padding(.top, 4)

            VStack(spacing: 8) {
                Button {
                    if let url = vm.paymentURL {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Reopen bunq", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.success))
                .disabled(vm.paymentURL == nil)

                Button("I already paid") {
                    vm.markPaidManually()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primary)

                Button("Cancel order") {
                    vm.cancel()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var paidContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.success.opacity(0.18))
                    .frame(width: 86, height: 86)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(AppTheme.success)
            }

            Text("Paid!")
                .font(.title.weight(.bold))
                .foregroundStyle(AppTheme.text)
            Text("\(recipe.name) is locked into your day. Delivery is on its way.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Helpers

    private var hasExclusions: Bool { !excludedItemIDs.isEmpty }
    private var hasIncludedItems: Bool { cart.items.contains { !excludedItemIDs.contains($0.id) } }
    private var filteredTotal: Double {
        cart.items
            .filter { !excludedItemIDs.contains($0.id) }
            .reduce(0) { $0 + $1.priceEur }
    }
    private var itemCountLabel: String {
        let total = cart.items.count
        let included = total - excludedItemIDs.intersection(cart.items.map(\.id)).count
        if included == total {
            return "\(total) items"
        }
        return "\(included) of \(total) items"
    }

    private func toggle(_ id: String) {
        if excludedItemIDs.contains(id) {
            excludedItemIDs.remove(id)
        } else {
            excludedItemIDs.insert(id)
        }
    }
}

// MARK: - Basket row

private struct BasketRow: View {
    let item: CartItem
    let isIncluded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    RemoteImageView(url: item.imageURL, cornerRadius: 14) {
                        ZStack {
                            AppTheme.mutedCard
                            Image(systemName: "fork.knife")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .grayscale(isIncluded ? 0 : 0.85)

                    Image(systemName: isIncluded ? "checkmark.circle.fill" : "minus.circle.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(isIncluded ? AppTheme.primary : AppTheme.secondaryText.opacity(0.7))
                        .background(Circle().fill(.white).frame(width: 18, height: 18))
                        .offset(x: 5, y: -5)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.productName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                        .strikethrough(!isIncluded, color: AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(item.ingredient.capitalized)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("€\(item.priceEur, specifier: "%.2f")")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .strikethrough(!isIncluded, color: AppTheme.secondaryText)
                        .monospacedDigit()
                    Text(qtyLabel)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(.vertical, 6)
            .opacity(isIncluded ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.productName), €\(item.priceEur, specifier: "%.2f")")
        .accessibilityHint(isIncluded ? "Tap to skip this item" : "Tap to add this item back")
        .accessibilityAddTraits(isIncluded ? [] : [.isSelected])
    }

    private var qtyLabel: String {
        let qty: String
        if item.qty.truncatingRemainder(dividingBy: 1) == 0 {
            qty = String(Int(item.qty))
        } else {
            qty = String(format: "%.1f", item.qty)
        }
        if let unit = item.unit, !unit.isEmpty {
            return "\(qty) × \(unit)"
        }
        return "Qty \(qty)"
    }
}
