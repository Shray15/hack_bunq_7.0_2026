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

    func checkout() async {
        guard let cart else { return }
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
                            Text("\(cart.items.count) items")
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
                        AppSectionHeader("Basket", detail: "Mapped from the recipe ingredients into actual store products.")

                        ForEach(cart.items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(AppTheme.primary.opacity(0.14))
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 7)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.productName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.text)
                                    Text(item.ingredient.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("€\(item.priceEur, specifier: "%.2f")")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(AppTheme.text)
                                    Text("Qty \(item.qty)")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
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
                        HStack {
                            Text("Total")
                                .font(.headline)
                                .foregroundStyle(AppTheme.text)
                            Spacer()
                            Text("€\(cart.totalEur, specifier: "%.2f")")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(AppTheme.primaryDeep)
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
                Task { await vm.checkout() }
            } label: {
                Group {
                    if vm.isOrdering {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Pay €\(cart.totalEur, specifier: "%.2f") via bunq", systemImage: "creditcard.fill")
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
