import SwiftUI

@MainActor
final class StoreComparisonViewModel: ObservableObject {
    @Published var comparison: CartComparisonResponse?
    @Published var isLoading: Bool = false
    @Published var loadingStore: String?
    @Published var errorMsg: String?

    private let api = APIService.shared

    func loadIfNeeded(recipe: Recipe, servings: Int) async {
        guard comparison == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            comparison = try await api.compareStores(recipeId: recipe.id, people: servings)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    /// Calls `/cart/{id}/select-store`, returning the items response. Sets
    /// `loadingStore` so the matching pill can show a spinner.
    func selectStore(_ store: String, cartId: String) async -> CartItemsResponse? {
        loadingStore = store
        defer { loadingStore = nil }
        do {
            return try await api.selectStore(cartId: cartId, store: store)
        } catch {
            errorMsg = error.localizedDescription
            return nil
        }
    }
}

struct StoreComparisonView: View {
    let recipe: Recipe
    let servings: Int
    let onClose: () -> Void

    @StateObject private var vm = StoreComparisonViewModel()
    @State private var selectedItems: CartItemsResponse?
    @State private var showError = false

    private var cheapestStore: String? {
        vm.comparison?.comparison.min { $0.totalEur < $1.totalEur }?.store
    }

    var body: some View {
        ZStack {
            AppBackground()

            Group {
                if let response = vm.comparison {
                    contentState(response)
                } else if vm.isLoading {
                    loadingState
                } else {
                    Color.clear
                }
            }
        }
        .navigationTitle("Pick your store")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", action: onClose)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .task { await vm.loadIfNeeded(recipe: recipe, servings: servings) }
        .navigationDestination(item: $selectedItems) { items in
            OrderCheckoutView(
                recipe: recipe,
                servings: servings,
                cart: items,
                onClose: onClose
            )
        }
        .onChange(of: vm.errorMsg) { _, value in
            showError = value != nil
        }
        .alert("Something went wrong", isPresented: $showError) {
            Button("OK") { vm.errorMsg = nil }
        } message: {
            Text(vm.errorMsg ?? "")
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView()
            Text("Comparing Albert Heijn and Picnic…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func contentState(_ response: CartComparisonResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AppCard(background: AppTheme.softPanel) {
                    VStack(alignment: .leading, spacing: 8) {
                        AppTag("Same recipe", color: AppTheme.success, icon: "fork.knife")
                        Text(recipe.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.text)
                        Text("Scaled for \(servings) \(servings == 1 ? "person" : "people"). Pick the store you'd like to order from — same shopping list, different totals.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                ForEach(response.comparison) { entry in
                    StoreComparisonCard(
                        entry: entry,
                        isCheapest: entry.store == cheapestStore,
                        isSelecting: vm.loadingStore == entry.store
                    ) {
                        Task {
                            if let items = await vm.selectStore(entry.store, cartId: response.cartId) {
                                selectedItems = items
                            }
                        }
                    }
                }
            }
            .appScrollContentPadding()
        }
    }
}

// MARK: - Store card

private struct StoreComparisonCard: View {
    let entry: StoreComparison
    let isCheapest: Bool
    let isSelecting: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(StoreCatalog.displayName(for: entry.store).uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.primary)
                                .textCase(.uppercase)
                            Text("€\(entry.totalEur, specifier: "%.2f")")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.text)
                                .monospacedDigit()
                        }

                        Spacer()

                        if isSelecting {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.title)
                                .foregroundStyle(AppTheme.primary)
                        }
                    }

                    HStack(spacing: 8) {
                        if isCheapest {
                            badge("Cheapest", icon: "checkmark.seal.fill", color: AppTheme.success)
                        }
                        badge(itemCountLabel, icon: "cart.fill", color: AppTheme.primary)
                        if entry.missingCount > 0 {
                            badge(missingLabel, icon: "exclamationmark.triangle.fill", color: AppTheme.accent)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isSelecting)
        .accessibilityLabel("\(StoreCatalog.displayName(for: entry.store)), €\(entry.totalEur, specifier: "%.2f"), \(entry.itemCount) items\(entry.missingCount > 0 ? ", \(entry.missingCount) missing" : "")")
    }

    private var itemCountLabel: String {
        let totalAvailable = entry.itemCount
        if entry.missingCount > 0 {
            return "\(totalAvailable) of \(totalAvailable + entry.missingCount) items"
        }
        return "\(totalAvailable) items"
    }

    private var missingLabel: String {
        entry.missingCount == 1 ? "1 unavailable" : "\(entry.missingCount) unavailable"
    }

    private func badge(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
