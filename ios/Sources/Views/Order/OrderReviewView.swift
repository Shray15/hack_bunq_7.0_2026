import UIKit
import SwiftUI

@MainActor
final class OrderViewModel: ObservableObject {
    @Published var paymentURL: URL?
    @Published var orderId: String?
    @Published var isOrdering: Bool = false
    @Published var isPaid: Bool = false
    @Published var errorMsg: String?

    /// Picker selection. Driven by the user from `PaymentMethodPicker`.
    @Published var selectedMethod: CheckoutPaymentMethod = .bunqMe

    /// Method actually used for the most recent successful checkout. Distinct
    /// from `selectedMethod` so the paid overlay reads stable state even if
    /// the user toggles the picker after paying.
    @Published private(set) var usedMethod: CheckoutPaymentMethod?

    private let api = APIService.shared
    private let realtime = RealtimeService.shared
    private var listenerTask: Task<Void, Never>?

    /// `POST /order/checkout`. With `selectedMethod == .bunqMe` this mints a
    /// bunq.me URL and we wait for an SSE `order_status: paid` event. With
    /// `selectedMethod == .mealCard` the backend debits the user's monthly
    /// meal-card sub-account synchronously and we short-circuit to paid.
    func checkout(cartId: String) async {
        isOrdering = true
        errorMsg = nil
        defer { isOrdering = false }
        do {
            let response = try await api.checkout(
                cartId: cartId,
                paymentMethod: selectedMethod
            )
            paymentURL = response.paymentURL.flatMap { URL(string: $0) }
            orderId = response.orderId
            usedMethod = selectedMethod
            if response.status == "paid" {
                isPaid = true
            } else {
                startWaitingForPayment()
            }
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
        usedMethod = nil
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

/// Final review step: read-only basket, total, payment-method picker, and
/// the bunq pay button. Pushed from `OrderCheckoutView` once the user taps
/// "Add to cart".
struct OrderReviewView: View {
    let recipe: Recipe
    let servings: Int
    let cartId: String
    let items: [CartItem]
    let totalEur: Double
    let store: String
    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = OrderViewModel()
    @State private var showError = false
    @State private var showShareSheet = false
    /// Snapshot of the meal-card balance taken right before the user paid via
    /// meal card. The paid overlay subtracts the cart total from this so it
    /// can show the post-payment balance without waiting for a refresh.
    @State private var balanceBeforePayment: Double?

    var body: some View {
        ZStack {
            AppBackground()
            content

            if shouldShowOverlay {
                paymentOverlay
                    .transition(.opacity)
            }
        }
        .navigationTitle("Review & pay")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", action: onClose)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .onChange(of: vm.paymentURL) { _, url in
            // Only auto-open for the bunq.me path; meal-card has no URL.
            if vm.usedMethod == .bunqMe, let url {
                UIApplication.shared.open(url)
            }
        }
        .onChange(of: vm.errorMsg) { _, value in
            showError = value != nil
        }
        .onChange(of: vm.isPaid) { _, paid in
            guard paid else { return }
            // For meal-card path: capture pre-payment balance for the paid
            // overlay, then refresh in the background.
            if vm.usedMethod == .mealCard {
                balanceBeforePayment = appState.currentMealCard?.currentBalanceEur
                Task { await appState.refreshMealCard() }
            }
            appState.completeOrder(recipe: recipe, servings: servings)
        }
        .alert("Something went wrong", isPresented: $showError) {
            Button("OK") { vm.errorMsg = nil }
        } message: {
            Text(vm.errorMsg ?? "")
        }
        .sheet(isPresented: $showShareSheet) {
            if let id = vm.orderId {
                ShareCostSheet(
                    orderId: id,
                    totalEur: totalEur,
                    recipeName: recipe.name
                )
            }
        }
        .animation(.easeOut(duration: 0.18), value: shouldShowOverlay)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                basketCard
                totalCard
                PaymentMethodPicker(
                    selected: $vm.selectedMethod,
                    amount: totalEur,
                    mealCard: appState.currentMealCard
                )
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
                    AppTag(StoreCatalog.displayName(for: store), color: AppTheme.success, icon: "cart.fill")
                    Spacer()
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Text(recipe.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                Text("Locked in for \(servings) \(servings == 1 ? "person" : "people"). Confirm and pay to release the order.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var basketCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                AppSectionHeader("In your cart", detail: "Final list — paid via bunq once you confirm.")

                ForEach(items) { item in
                    BasketRow(item: item, isIncluded: true, onToggle: nil)

                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var totalCard: some View {
        AppCard(background: AppTheme.mutedCard) {
            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Text("€\(totalEur, specifier: "%.2f")")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .monospacedDigit()
            }
        }
    }

    private var payButton: some View {
        Button {
            Task { await vm.checkout(cartId: cartId) }
        } label: {
            Group {
                if vm.isOrdering {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Label(payButtonLabel, systemImage: payButtonIcon)
                }
            }
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.success))
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .disabled(vm.isOrdering)
    }

    private var payButtonLabel: String {
        let amount = String(format: "%.2f", totalEur)
        switch vm.selectedMethod {
        case .bunqMe:   return "Pay €\(amount) via bunq"
        case .mealCard: return "Pay €\(amount) with Meal Card"
        }
    }

    private var payButtonIcon: String {
        switch vm.selectedMethod {
        case .bunqMe:   return "creditcard.fill"
        case .mealCard: return "creditcard.and.123"
        }
    }

    // MARK: - Payment overlay

    private var shouldShowOverlay: Bool {
        // For meal-card path the URL is always nil, so we trigger off
        // isOrdering or isPaid only.
        if vm.usedMethod == .mealCard {
            return vm.isOrdering || vm.isPaid
        }
        return vm.isOrdering || vm.paymentURL != nil || vm.isPaid
    }

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
                Image(systemName: vm.usedMethod == .mealCard ? "creditcard.and.123" : "creditcard.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.success)
            }

            Text(vm.usedMethod == .mealCard ? "Charging your meal card…" : "Confirm in bunq")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.text)
            Text(vm.usedMethod == .mealCard
                 ? "We're moving the funds from your meal-card sub-account."
                 : "We'll mark this paid the moment bunq confirms — usually a few seconds.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)

            ProgressView()
                .padding(.top, 4)

            if vm.usedMethod != .mealCard {
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

            Text(paidTitle)
                .font(.title.weight(.bold))
                .foregroundStyle(AppTheme.text)
            Text(paidSubtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if vm.usedMethod == .mealCard {
                Text("Sandbox demo — no real order is placed at AH/Picnic. In production, AH/Picnic would charge this card directly.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            VStack(spacing: 10) {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Split the cost with friends", systemImage: "person.2.fill")
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(vm.orderId == nil)

                Button("Done", action: onClose)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Paid copy (varies by method)

    private var paidTitle: String {
        vm.usedMethod == .mealCard ? "Order placed!" : "Paid!"
    }

    private var paidSubtitle: String {
        if vm.usedMethod == .mealCard, let before = balanceBeforePayment {
            let after = max(0, before - totalEur)
            return "€\(String(format: "%.2f", after)) remaining on your meal card. Delivery is on its way."
        }
        return "\(recipe.name) is locked into your day. Delivery is on its way."
    }
}
