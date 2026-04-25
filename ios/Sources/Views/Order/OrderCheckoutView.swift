import UIKit
import SwiftUI

@MainActor
class OrderViewModel: ObservableObject {
    @Published var cart: CartResponse?
    @Published var isLoading = false
    @Published var isOrdering = false
    @Published var paymentURL: URL?
    @Published var errorMsg: String?

    private let api = APIService.shared

    func load(recipe: Recipe, people: Int) async {
        isLoading = true
        do {
            cart = try await api.buildCart(from: recipe, people: people)
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }

    func checkout(cart: CartResponse) async {
        isOrdering = true
        do {
            let response = try await api.checkout(cart: cart)
            paymentURL = URL(string: response.paymentURL)
        } catch {
            errorMsg = error.localizedDescription
        }
        isOrdering = false
    }
}

struct OrderCheckoutView: View {
    let recipe: Recipe
    let servings: Int

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = OrderViewModel()
    @State private var showError = false
    @State private var showBunqConnect = false
    @State private var excludedItemIDs: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Group {
                    if vm.isLoading {
                        loadingState
                    } else if let cart = vm.cart {
                        cartState(cart)
                    } else {
                        Color.clear
                    }
                }
            }
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .task { await vm.load(recipe: recipe, people: servings) }
            .onChange(of: vm.paymentURL) {
                if let url = vm.paymentURL {
                    appState.completeOrder(recipe: recipe, servings: servings)
                    UIApplication.shared.open(url)
                    dismiss()
                }
            }
            .onChange(of: vm.errorMsg) {
                if vm.errorMsg != nil {
                    showError = true
                }
            }
            .alert("Something went wrong", isPresented: $showError) {
                Button("OK") {
                    vm.errorMsg = nil
                }
            } message: {
                Text(vm.errorMsg ?? "")
            }
            .sheet(isPresented: $showBunqConnect) {
                BunqConnectSheet(isConnected: $appState.bunqConnected)
            }
        }
    }

    private var loadingState: some View {
        VStack {
            AppCard {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Building your basket...")
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text("We are matching ingredients, quantities, and prices.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
        }
    }

    private func cartState(_ cart: CartResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AppCard(background: Color(red: 0.90, green: 0.97, blue: 0.93)) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            AppTag(storeLabel(for: cart.store), color: AppTheme.success, icon: "cart.fill")
                            Spacer()
                            Text(itemCountLabel(cart))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        Text(recipe.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(AppTheme.text)

                        Text(checkoutSummaryText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 16) {
                        AppSectionHeader("Basket", detail: "Tap anything you already have at home.")

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

                AppCard(background: AppTheme.mutedCard) {
                    VStack(spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Total")
                                .font(.headline)
                                .foregroundStyle(AppTheme.text)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("€\(filteredTotal(cart), specifier: "%.2f")")
                                    .font(.title2)
                                    .fontWeight(.bold)
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
                            AppTag(appState.bunqConnected ? "bunq connected" : "bunq required", color: appState.bunqConnected ? AppTheme.success : AppTheme.accent, icon: "creditcard.fill")
                            Spacer()
                            Text(appState.bunqConnected ? "Ready to pay" : "Connect before paying")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
            }
            .appScrollContentPadding()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if appState.bunqConnected {
                    Task { await vm.checkout(cart: filteredCart(cart)) }
                } else {
                    showBunqConnect = true
                }
            } label: {
                Group {
                    if vm.isOrdering {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else if !hasIncludedItems(cart) {
                        Label("Add an item to checkout", systemImage: "cart.badge.minus")
                    } else if !appState.bunqConnected {
                        Label("Connect bunq to pay", systemImage: "creditcard.fill")
                    } else {
                        Label(
                            "Pay €\(filteredTotal(cart), specifier: "%.2f") via bunq",
                            systemImage: "creditcard.fill"
                        )
                    }
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.success))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            .disabled(vm.isOrdering || !hasIncludedItems(cart))
        }
    }

    private var checkoutSummaryText: String {
        let people = "\(servings) \(servings == 1 ? "person" : "people")"
        if appState.bunqConnected {
            return "Scaled for \(people). Confirm once and the order moves into your day."
        }
        return "Scaled for \(people). Connect bunq to finish checkout."
    }

    private func toggle(_ id: String) {
        if excludedItemIDs.contains(id) {
            excludedItemIDs.remove(id)
        } else {
            excludedItemIDs.insert(id)
        }
    }

    private var hasExclusions: Bool {
        !excludedItemIDs.isEmpty
    }

    private func hasIncludedItems(_ cart: CartResponse) -> Bool {
        cart.items.contains { !excludedItemIDs.contains($0.id) }
    }

    private func filteredItems(_ cart: CartResponse) -> [CartItem] {
        cart.items.filter { !excludedItemIDs.contains($0.id) }
    }

    private func filteredTotal(_ cart: CartResponse) -> Double {
        filteredItems(cart).reduce(0) { $0 + $1.priceEur }
    }

    private func filteredCart(_ cart: CartResponse) -> CartResponse {
        let items = filteredItems(cart)
        let total = items.reduce(0) { $0 + $1.priceEur }
        return CartResponse(items: items, totalEur: total, store: cart.store)
    }

    private func itemCountLabel(_ cart: CartResponse) -> String {
        let included = cart.items.count - excludedItemIDs.intersection(cart.items.map(\.id)).count
        if included == cart.items.count {
            return "\(cart.items.count) items"
        }
        return "\(included) of \(cart.items.count) items"
    }

    private func storeLabel(for store: String) -> String {
        switch store.lowercased() {
        case "ah":
            return "Albert Heijn"
        default:
            return store.uppercased()
        }
    }
}

private struct BasketRow: View {
    let item: CartItem
    let isIncluded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isIncluded ? AppTheme.primary : AppTheme.secondaryText.opacity(0.55))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.productName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                        .strikethrough(!isIncluded, color: AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                    Text(item.ingredient.capitalized)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("€\(item.priceEur, specifier: "%.2f")")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .strikethrough(!isIncluded, color: AppTheme.secondaryText)
                    Text("Qty \(item.qty)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(.vertical, 6)
            .opacity(isIncluded ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.productName), €\(item.priceEur, specifier: "%.2f")")
        .accessibilityHint(isIncluded ? "Tap to skip this item" : "Tap to add this item back")
        .accessibilityAddTraits(isIncluded ? [] : [.isSelected])
    }
}
