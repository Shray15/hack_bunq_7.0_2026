import SwiftUI

/// Dedicated meal-card screen pushed from the Home tile. Shows a hero
/// virtual-card visual, balance/budget metrics, top-up button, and the
/// transaction list.
struct MealCardScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var transactions: [MealCardTransaction] = []
    @State private var loadingTx: Bool = false
    @State private var errorMsg: String?
    @State private var showTopUp: Bool = false
    @State private var showAbout: Bool = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let card = appState.currentMealCard {
                        HeroCard(card: card)
                        balanceMetrics(card: card)
                        topUpButton
                        transactionsSection
                        aboutDisclosure
                    } else {
                        emptyState
                    }
                }
                .appScrollContentPadding()
            }
            .refreshable {
                await refreshAll()
            }
        }
        .navigationTitle("Meal card")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshAll()
        }
        .sheet(isPresented: $showTopUp) {
            MealCardTopUpSheet()
                .environmentObject(appState)
        }
    }

    // MARK: - Sections

    private func balanceMetrics(card: MealCard) -> some View {
        HStack(spacing: 12) {
            MetricChip(
                title: "Remaining",
                value: "€\(amountString(card.currentBalanceEur))",
                icon: "wallet.pass.fill",
                tint: AppTheme.primary
            )
            MetricChip(
                title: "Spent",
                value: "€\(amountString(card.spentEur))",
                icon: "arrow.up.right.circle.fill",
                tint: AppTheme.accent
            )
        }
    }

    private var topUpButton: some View {
        Button {
            showTopUp = true
        } label: {
            Label("Top up", systemImage: "plus.circle.fill")
        }
        .buttonStyle(AppPrimaryButtonStyle())
    }

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AppSectionHeader("Recent activity", eyebrow: "Transactions")
                Spacer()
                if loadingTx {
                    ProgressView().controlSize(.small)
                }
            }

            if let errorMsg {
                Text(errorMsg)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if transactions.isEmpty && !loadingTx {
                AppCard(padding: 18, background: AppTheme.mutedCard) {
                    HStack(spacing: 12) {
                        Image(systemName: "tray")
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("No activity yet. Pay for groceries with this card to see them here.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(transactions) { tx in
                        MealCardTransactionRow(tx: tx)
                    }
                }
            }
        }
    }

    private var aboutDisclosure: some View {
        DisclosureGroup(isExpanded: $showAbout) {
            VStack(alignment: .leading, spacing: 10) {
                Text("This card is backed by a real bunq sandbox sub-account. The IBAN above is live in the bunq sandbox.")
                Text("In production, AH and Picnic would charge this card directly at checkout. In this sandbox demo, we simulate the merchant charge by moving the amount back to your primary bunq account.")
                if let card = appState.currentMealCard {
                    HStack {
                        Text("IBAN")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Text(card.formattedIban)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.text)
                    }
                    .padding(.top, 4)
                }
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.top, 6)
        } label: {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppTheme.primary)
                Text("About this card")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
            }
        }
        .padding(16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppTheme.primary.opacity(0.7))
                .padding(.top, 40)
            Text("No meal card yet for this month.")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text("Head back to Home and tap the meal card tile to set one up.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private func refreshAll() async {
        await appState.refreshMealCard()
        await loadTransactions()
    }

    private func loadTransactions() async {
        // Don't bother fetching transactions if there's no card to fetch them for.
        guard appState.currentMealCard != nil else {
            transactions = []
            return
        }
        loadingTx = true
        errorMsg = nil
        defer { loadingTx = false }
        do {
            transactions = try await APIService.shared.getMealCardTransactions(limit: 50)
        } catch {
            errorMsg = "Could not load transactions: \(error.localizedDescription)"
        }
    }

    private func amountString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

// MARK: - Hero card visual

private struct HeroCard: View {
    let card: MealCard

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BUNQ MEAL CARD")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.92))
                    Text(card.displayMonth)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "wave.3.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 18)

            Text("•••• •••• •••• \(card.last4 ?? "0000")")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Balance")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("€\(String(format: "%.2f", card.currentBalanceEur))")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Expires")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(card.expiresAt, format: .dateTime.month(.twoDigits).year(.twoDigits))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.primaryDeep,
                    AppTheme.primary,
                    AppTheme.primary.opacity(0.85),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 200, height: 200)
                .blur(radius: 14)
                .offset(x: 70, y: -90)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AppTheme.primaryDeep.opacity(0.30), radius: 24, y: 16)
    }
}

// MARK: - Top-up sheet

private struct MealCardTopUpSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = "50"
    @State private var isToppingUp: Bool = false
    @State private var errorMsg: String?

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Top up your meal card")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.text)
                        Text("Move funds from your primary bunq account onto the meal card.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)

                        AppCard(padding: 14) {
                            HStack(spacing: 10) {
                                Text("€")
                                    .font(.title.weight(.semibold))
                                    .foregroundStyle(AppTheme.secondaryText)
                                TextField("Amount", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .font(.title.weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                            }
                        }

                        HStack(spacing: 8) {
                            ForEach([25, 50, 100], id: \.self) { quick in
                                Button("+€\(quick)") { amountText = String(quick) }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.primary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        if let errorMsg {
                            Text(errorMsg)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .appScrollContentPadding()
                }
                VStack {
                    Spacer()
                    Button {
                        Task { await topUp() }
                    } label: {
                        HStack {
                            if isToppingUp {
                                ProgressView().tint(.white)
                            }
                            Text(isToppingUp ? "Topping up…" : "Top up €\(String(format: "%.2f", amount))")
                        }
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(isToppingUp || amount <= 0)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Top up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isToppingUp)
                }
            }
        }
    }

    private func topUp() async {
        isToppingUp = true
        errorMsg = nil
        defer { isToppingUp = false }
        do {
            let card = try await APIService.shared.topUpMealCard(amountEur: amount)
            appState.setMealCard(card)
            dismiss()
        } catch {
            errorMsg = "Top-up failed: \(error.localizedDescription)"
        }
    }
}
