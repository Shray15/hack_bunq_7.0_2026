import UIKit
import SwiftUI

@MainActor
class OrderViewModel: ObservableObject {
    @Published var cart: CartResponse?
    @Published var isLoading = false
    @Published var isSwitching = false
    @Published var isOrdering = false
    @Published var paymentURL: URL?
    @Published var errorMsg: String?

    private let api = APIService.shared

    func load(recipe: Recipe, people: Int, store: String? = nil) async {
        if cart == nil {
            isLoading = true
        } else {
            isSwitching = true
        }
        defer {
            isLoading = false
            isSwitching = false
        }
        do {
            cart = try await api.buildCart(from: recipe, people: people, store: store)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    func switchStore(to store: String, recipe: Recipe, people: Int) async {
        guard cart?.selectedStore != store else { return }
        await load(recipe: recipe, people: people, store: store)
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
                    Text("Comparing Albert Heijn and Picnic for the cheapest match.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
        }
    }

    private func cartState(_ cart: CartResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard(cart)

                if !cart.comparison.isEmpty {
                    storeSwitcherCard(cart)
                }

                basketCard(cart)
                totalCard(cart)
            }
            .appScrollContentPadding()
        }
        .safeAreaInset(edge: .bottom) {
            payButton(cart)
        }
    }

    // MARK: - Summary

    private func summaryCard(_ cart: CartResponse) -> some View {
        AppCard(background: Color(red: 0.90, green: 0.97, blue: 0.93)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    AppTag(StoreCatalog.displayName(for: currentStore(cart)), color: AppTheme.success, icon: "cart.fill")
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
    }

    // MARK: - Store switcher

    private func storeSwitcherCard(_ cart: CartResponse) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader("Pick your store", detail: "One store per order. We default to the cheapest match.")

                StoreSwitcher(
                    comparison: cart.comparison,
                    selectedStore: currentStore(cart),
                    isSwitching: vm.isSwitching
                ) { store in
                    excludedItemIDs.removeAll()
                    Task { await vm.switchStore(to: store, recipe: recipe, people: servings) }
                }
            }
        }
    }

    // MARK: - Basket

    private func basketCard(_ cart: CartResponse) -> some View {
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
            .opacity(vm.isSwitching ? 0.5 : 1)
            .animation(.easeOut(duration: 0.18), value: vm.isSwitching)
        }
    }

    // MARK: - Total

    private func totalCard(_ cart: CartResponse) -> some View {
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
                    AppTag("Pay via bunq", color: AppTheme.success, icon: "creditcard.fill")
                    Spacer()
                    Text("bunq.me payment opens after checkout")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    // MARK: - Pay button

    private func payButton(_ cart: CartResponse) -> some View {
        Button {
            Task { await vm.checkout(cart: filteredCart(cart)) }
        } label: {
            Group {
                if vm.isOrdering {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else if !hasIncludedItems(cart) {
                    Label("Add an item to checkout", systemImage: "cart.badge.minus")
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
        .disabled(vm.isOrdering || vm.isSwitching || !hasIncludedItems(cart))
    }

    // MARK: - Helpers

    private func currentStore(_ cart: CartResponse) -> String {
        cart.selectedStore ?? cart.comparison.first?.store ?? "ah"
    }

    private var checkoutSummaryText: String {
        let people = "\(servings) \(servings == 1 ? "person" : "people")"
        return "Scaled for \(people). Confirm once and the order moves into your day."
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
        return CartResponse(
            id: cart.id,
            recipeId: cart.recipeId,
            status: cart.status,
            selectedStore: cart.selectedStore,
            comparison: cart.comparison,
            items: items
        )
    }

    private func itemCountLabel(_ cart: CartResponse) -> String {
        let included = cart.items.count - excludedItemIDs.intersection(cart.items.map(\.id)).count
        if included == cart.items.count {
            return "\(cart.items.count) items"
        }
        return "\(included) of \(cart.items.count) items"
    }
}

// MARK: - Store switcher components

private struct StoreSwitcher: View {
    let comparison: [StoreComparison]
    let selectedStore: String
    let isSwitching: Bool
    let onSelect: (String) -> Void

    private var cheapestStore: String? {
        comparison.min { $0.totalEur < $1.totalEur }?.store
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(comparison) { entry in
                StorePill(
                    entry: entry,
                    isSelected: entry.store == selectedStore,
                    isCheapest: entry.store == cheapestStore,
                    isSwitching: isSwitching && entry.store == selectedStore
                ) {
                    onSelect(entry.store)
                }
            }
        }
    }
}

private struct StorePill: View {
    let entry: StoreComparison
    let isSelected: Bool
    let isCheapest: Bool
    let isSwitching: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isSelected ? AppTheme.success : AppTheme.secondaryText.opacity(0.6))
                    Text(StoreCatalog.displayName(for: entry.store))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                }

                Text("€\(entry.totalEur, specifier: "%.2f")")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isSelected ? AppTheme.primaryDeep : AppTheme.text)
                    .monospacedDigit()

                HStack(spacing: 6) {
                    if isCheapest {
                        badge("Cheapest", color: AppTheme.success)
                    }
                    if entry.missingCount > 0 {
                        badge("\(entry.missingCount) missing", color: AppTheme.accent)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isSelected ? AppTheme.success.opacity(0.10) : AppTheme.card)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? AppTheme.success : AppTheme.stroke, lineWidth: isSelected ? 1.5 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isSwitching {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                }
            }
            .opacity(isSwitching ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isSwitching || isSelected)
        .accessibilityLabel("\(StoreCatalog.displayName(for: entry.store)), €\(entry.totalEur, specifier: "%.2f")\(isCheapest ? ", cheapest option" : "")")
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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
        let q = item.qty
        if q.truncatingRemainder(dividingBy: 1) == 0 {
            return "Qty \(Int(q))"
        }
        return String(format: "Qty %.1f", q)
    }
}
