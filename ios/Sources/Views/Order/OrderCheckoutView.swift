import UIKit
import SwiftUI

/// First step of checkout: the user reviews the basket the backend matched
/// for the chosen store, skips anything they already have at home, and taps
/// "Add to cart" to advance to the bunq pay screen.
struct OrderCheckoutView: View {
    let recipe: Recipe
    let servings: Int
    let cart: CartItemsResponse
    let onClose: () -> Void

    @State private var excludedItemIDs: Set<String> = []
    @State private var navigateToReview = false

    var body: some View {
        ZStack {
            AppBackground()
            cartContent
        }
        .navigationTitle("Your basket")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", action: onClose)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .navigationDestination(isPresented: $navigateToReview) {
            OrderReviewView(
                recipe: recipe,
                servings: servings,
                cartId: cart.cartId,
                items: filteredItems,
                totalEur: filteredTotal,
                store: cart.selectedStore,
                onClose: onClose
            )
        }
    }

    // MARK: - Content

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
            addToCartButton
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
                        isIncluded: !excludedItemIDs.contains(item.id),
                        onToggle: { toggle(item.id) }
                    )

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
                    Text("Subtotal")
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
                    AppTag("Add to cart", color: AppTheme.primary, icon: "cart.fill")
                    Spacer()
                    Text("Pay on the next step")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private var addToCartButton: some View {
        Button {
            navigateToReview = true
        } label: {
            Group {
                if !hasIncludedItems {
                    Label("Add an item to checkout", systemImage: "cart.badge.minus")
                } else {
                    Label("Add to cart (€\(filteredTotal, specifier: "%.2f"))", systemImage: "cart.fill")
                }
            }
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.primary))
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .disabled(!hasIncludedItems)
    }

    // MARK: - Helpers

    private var hasExclusions: Bool { !excludedItemIDs.isEmpty }
    private var hasIncludedItems: Bool { cart.items.contains { !excludedItemIDs.contains($0.id) } }
    private var filteredItems: [CartItem] {
        cart.items.filter { !excludedItemIDs.contains($0.id) }
    }
    private var filteredTotal: Double {
        filteredItems.reduce(0) { $0 + $1.priceEur }
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

// MARK: - Basket row (shared with OrderReviewView)

/// Single row in either the basket-edit screen or the review screen.
/// Pass `onToggle = nil` for the read-only review case.
struct BasketRow: View {
    let item: CartItem
    let isIncluded: Bool
    let onToggle: (() -> Void)?

    var body: some View {
        Button {
            onToggle?()
        } label: {
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

                    if onToggle != nil {
                        Image(systemName: isIncluded ? "checkmark.circle.fill" : "minus.circle.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(isIncluded ? AppTheme.primary : AppTheme.secondaryText.opacity(0.7))
                            .background(Circle().fill(.white).frame(width: 18, height: 18))
                            .offset(x: 5, y: -5)
                    }
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
        .disabled(onToggle == nil)
        .accessibilityLabel("\(item.productName), €\(item.priceEur, specifier: "%.2f")")
        .accessibilityHint(onToggle == nil ? "" : (isIncluded ? "Tap to skip this item" : "Tap to add this item back"))
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
