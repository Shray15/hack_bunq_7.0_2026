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

    @StateObject private var vm = OrderViewModel()
    @State private var deliveryIndex = 0
    @State private var showError = false
    @State private var excludedItemIDs: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    private let deliveryOptions = ["Today", "Tomorrow", "Pick a date"]

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
        }
    }

    private var loadingState: some View {
        VStack {
            AppCard {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Matching ingredients to real products...")
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text("This is the handoff from recipe to grocery cart.")
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

                        Text("Scaled for \(servings) \(servings == 1 ? "person" : "people"). Ready to pay through bunq when you confirm.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 16) {
                        AppSectionHeader("Basket", detail: "Tap an item to skip it if you already have it at home.")

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

                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        AppSectionHeader("Delivery", detail: "Keep this simple for the demo. Time slot depth can come later.")

                        HStack(spacing: 10) {
                            ForEach(Array(deliveryOptions.enumerated()), id: \.offset) { index, option in
                                Button {
                                    deliveryIndex = index
                                } label: {
                                    Text(option)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(deliveryIndex == index ? .white : AppTheme.text)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(deliveryIndex == index ? AppTheme.primary : AppTheme.mutedCard)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
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
                            AppTag("bunq checkout", color: AppTheme.success, icon: "creditcard.fill")
                            Spacer()
                            Text("Sandbox ready")
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
                Task { await vm.checkout(cart: filteredCart(cart)) }
            } label: {
                Group {
                    if vm.isOrdering {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else if hasIncludedItems(cart) {
                        Label(
                            "Pay €\(filteredTotal(cart), specifier: "%.2f") via bunq",
                            systemImage: "creditcard.fill"
                        )
                    } else {
                        Label("Add an item to checkout", systemImage: "cart.badge.minus")
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
