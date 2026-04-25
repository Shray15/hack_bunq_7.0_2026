import SwiftUI

/// First-run setup sheet for the monthly meal card. User picks a budget,
/// taps "Create card", and on success the parent dismisses this and refreshes
/// the Home tile.
struct MealCardSetupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private let presets: [Double] = [100, 200, 300, 500]

    @State private var selectedBudget: Double = 300
    @State private var customAmountText: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        presetGrid
                        customField
                        if let errorMsg {
                            Text(errorMsg)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        explainer
                    }
                    .appScrollContentPadding()
                }
                VStack {
                    Spacer()
                    createButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Meal card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set your monthly grocery budget")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.text)
            Text("We'll create a virtual bunq card with this budget. Every grocery checkout can be paid from it, and the balance updates live.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(presets, id: \.self) { preset in
                Button {
                    selectedBudget = preset
                    customAmountText = ""
                } label: {
                    PresetTile(
                        amount: preset,
                        isSelected: isPresetSelected(preset)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customField: some View {
        AppCard(padding: 14) {
            HStack(spacing: 10) {
                Text("€")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                TextField("Custom amount", text: $customAmountText)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .onChange(of: customAmountText) { _, newValue in
                        if let value = parseAmount(newValue) {
                            selectedBudget = value
                        }
                    }
                if !customAmountText.isEmpty {
                    Button {
                        customAmountText = ""
                        selectedBudget = 300
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureRow(
                icon: "shield.lefthalf.filled",
                title: "Real bunq sandbox card",
                detail: "We create a sub-account on your bunq sandbox profile and issue a virtual debit card."
            )
            DisclosureRow(
                icon: "arrow.up.arrow.down.circle.fill",
                title: "Top up any time",
                detail: "Add more funds during the month if your budget runs low."
            )
            DisclosureRow(
                icon: "calendar",
                title: "Refreshes monthly",
                detail: "Card auto-rolls over on the 1st. Each month you can set a new budget."
            )
        }
        .padding(.top, 4)
    }

    private var createButton: some View {
        Button {
            Task { await create() }
        } label: {
            HStack {
                if isCreating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(isCreating ? "Creating your card…" : "Create card · €\(amountString(selectedBudget))")
            }
        }
        .buttonStyle(AppPrimaryButtonStyle())
        .disabled(isCreating || selectedBudget <= 0)
    }

    // MARK: - Actions

    private func create() async {
        isCreating = true
        errorMsg = nil
        defer { isCreating = false }
        do {
            let card = try await APIService.shared.createMealCard(budgetEur: selectedBudget)
            appState.setMealCard(card)
            dismiss()
        } catch {
            errorMsg = "Could not create your meal card: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func isPresetSelected(_ amount: Double) -> Bool {
        customAmountText.isEmpty && abs(selectedBudget - amount) < 0.01
    }

    private func parseAmount(_ raw: String) -> Double? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func amountString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private struct PresetTile: View {
    let amount: Double
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("€\(Int(amount))")
                .font(.title2.weight(.bold))
                .foregroundStyle(isSelected ? .white : AppTheme.text)
            Text("for the month")
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.8) : AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(isSelected ? AppTheme.primary : AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? AppTheme.primaryDeep : AppTheme.stroke, lineWidth: 1)
        }
        .shadow(
            color: isSelected ? AppTheme.primary.opacity(0.25) : .black.opacity(0.04),
            radius: isSelected ? 12 : 8,
            y: 6
        )
    }
}

private struct DisclosureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 28, height: 28)
                .background(AppTheme.primary.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
