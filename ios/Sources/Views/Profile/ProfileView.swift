import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showBunqConnect = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        identityCard
                        goalsCard
                        paymentCard
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showBunqConnect) {
                BunqConnectSheet(isConnected: $appState.bunqConnected)
            }
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
        AppCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.primary, AppTheme.primaryDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(initials)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                .shadow(color: AppTheme.primary.opacity(0.22), radius: 14, y: 8)

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Your name", text: $appState.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFieldFocused)
                        .onSubmit { nameFieldFocused = false }

                    Text(dietSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var initials: String {
        let parts = appState.displayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        return parts.isEmpty ? "?" : parts.joined()
    }

    private var dietSubtitle: String {
        let calories = "\(appState.dailyCalorieTarget) kcal/day"
        let people = appState.householdSize == 1 ? "solo" : "\(appState.householdSize) people"
        return "\(appState.dietType.rawValue) · \(calories) · \(people)"
    }

    // MARK: - Goals

    private var goalsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Goals")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                dietRow
                Divider()

                HStack(spacing: 12) {
                    AppIconValueRow(
                        icon: "flame.fill",
                        tint: AppTheme.accent,
                        title: "Daily calorie target",
                        value: "\(appState.dailyCalorieTarget) kcal"
                    )
                    InlineStepper(
                        value: $appState.dailyCalorieTarget,
                        range: 1200...4000,
                        step: 50
                    )
                }

                Divider()

                HStack(spacing: 12) {
                    AppIconValueRow(
                        icon: "person.2.fill",
                        tint: AppTheme.primary,
                        title: "Default household",
                        value: "\(appState.householdSize) \(appState.householdSize == 1 ? "person" : "people")"
                    )
                    InlineStepper(
                        value: $appState.householdSize,
                        range: 1...10,
                        step: 1
                    )
                }
            }
        }
    }

    private var dietRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(AppTheme.primary)
                .frame(width: 34, height: 34)
                .background(AppTheme.primary.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Diet style")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(appState.dietType.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
            }

            Spacer()

            Menu {
                ForEach(DietType.allCases, id: \.rawValue) { diet in
                    Button {
                        appState.dietType = diet
                    } label: {
                        if diet == appState.dietType {
                            Label(diet.rawValue, systemImage: "checkmark")
                        } else {
                            Text(diet.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Change")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(AppTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.primary.opacity(0.12))
                .clipShape(Capsule())
            }
            .accessibilityLabel("Change diet style")
        }
    }

    // MARK: - Payment

    private var paymentCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Payment")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                if appState.bunqConnected {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.success.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("bunq linked")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.text)
                            Text("Checkout opens a payment request directly.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        Spacer()
                    }
                } else {
                    Button {
                        showBunqConnect = true
                    } label: {
                        Label("Connect bunq account", systemImage: "creditcard.fill")
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.success))
                }
            }
        }
    }

}

// MARK: - Inline stepper

private struct InlineStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 0) {
            stepperButton(systemImage: "minus", enabled: value > range.lowerBound) {
                let next = value - step
                value = max(next, range.lowerBound)
            }
            .accessibilityLabel("Decrease")

            stepperButton(systemImage: "plus", enabled: value < range.upperBound) {
                let next = value + step
                value = min(next, range.upperBound)
            }
            .accessibilityLabel("Increase")
        }
        .background(AppTheme.mutedCard)
        .overlay {
            Capsule()
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
        .clipShape(Capsule())
    }

    private func stepperButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? AppTheme.primary : AppTheme.secondaryText.opacity(0.4))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Bunq connect sheet

struct BunqConnectSheet: View {
    @Binding var isConnected: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 20) {
                    Spacer()

                    Circle()
                        .fill(AppTheme.success.opacity(0.14))
                        .frame(width: 90, height: 90)
                        .overlay {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(AppTheme.success)
                        }

                    VStack(spacing: 10) {
                        Text("Connect bunq")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(AppTheme.text)
                        Text("Link a bunq account so checkout can open a payment request immediately after the cart is built.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, 28)

                    Spacer()

                    VStack(spacing: 12) {
                        Button {
                            isConnected = true
                            dismiss()
                        } label: {
                            Text("Connect with bunq")
                        }
                        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.success))

                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Connect bunq")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
