import SwiftUI

struct ProfileView: View {
    @AppStorage("dietType") private var dietTypeRaw = DietType.balanced.rawValue
    @AppStorage("calorieTarget") private var calorieTarget = 2000
    @AppStorage("householdSize") private var householdSize = 1
    @AppStorage("bunqConnected") private var bunqConnected = false
    @State private var showBunqConnect = false

    private var dietType: DietType {
        DietType(rawValue: dietTypeRaw) ?? .balanced
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        AppCard {
                            VStack(alignment: .leading, spacing: 16) {
                                AppSectionHeader(
                                    "Profile and goals",
                                    eyebrow: "Settings",
                                    detail: "These values shape recipe suggestions, portion sizing, and the nutrition view."
                                )

                                Picker("Diet type", selection: $dietTypeRaw) {
                                    ForEach(DietType.allCases, id: \.rawValue) { diet in
                                        Text(diet.rawValue).tag(diet.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)

                                VStack(spacing: 12) {
                                    Stepper(value: $calorieTarget, in: 1200...4000, step: 50) {
                                        AppIconValueRow(
                                            icon: "flame.fill",
                                            tint: AppTheme.accent,
                                            title: "Daily calorie target",
                                            value: "\(calorieTarget) kcal"
                                        )
                                    }

                                    Stepper(value: $householdSize, in: 1...10) {
                                        AppIconValueRow(
                                            icon: "person.2.fill",
                                            tint: AppTheme.primary,
                                            title: "Default household",
                                            value: "\(householdSize) \(householdSize == 1 ? "person" : "people")"
                                        )
                                    }
                                }
                                .padding(14)
                                .background(AppTheme.mutedCard)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 16) {
                                AppSectionHeader("Current focus", detail: "Small summary tiles make the profile screen feel alive.")

                                HStack(spacing: 12) {
                                    MetricChip(title: "Diet", value: dietType.rawValue, icon: "leaf.fill", tint: AppTheme.primary)
                                    MetricChip(title: "bunq", value: bunqConnected ? "Connected" : "Not linked", icon: "creditcard.fill", tint: bunqConnected ? AppTheme.success : AppTheme.accent)
                                }
                            }
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 16) {
                                AppSectionHeader("Payment", detail: "For the demo this can stay instant. The real version becomes OAuth.")

                                if bunqConnected {
                                    HStack {
                                        AppTag("bunq connected", color: AppTheme.success, icon: "checkmark.circle.fill")
                                        Spacer()
                                        Button("Disconnect", role: .destructive) {
                                            bunqConnected = false
                                        }
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

                        AppCard(background: AppTheme.mutedCard) {
                            HStack {
                                Text("Version")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.secondaryText)
                                Spacer()
                                Text("1.0.0 · hackathon build")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.text)
                            }
                        }
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showBunqConnect) {
                BunqConnectSheet(isConnected: $bunqConnected)
            }
        }
    }
}

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
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
