import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe
    @EnvironmentObject private var appState: AppState
    @State private var servings: Int?
    @State private var showingOrder = false
    @State private var showInstructions = false

    private var currentServings: Binding<Int> {
        Binding(
            get: { servings ?? appState.householdSize },
            set: { servings = $0 }
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero

                    statsCard

                    AppCard {
                        VStack(alignment: .leading, spacing: 16) {
                            AppSectionHeader("Ingredients", detail: "Scaled live for the number of people you are cooking for.")

                            HStack(spacing: 12) {
                                Text("Servings")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.text)
                                Spacer()
                                ServingsStepper(value: currentServings, range: 1...12)
                            }

                            ForEach(recipe.ingredients) { item in
                                HStack(alignment: .center, spacing: 12) {
                                    Circle()
                                        .fill(AppTheme.primary.opacity(0.18))
                                        .frame(width: 10, height: 10)
                                    Text(item.name.capitalized)
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.text)
                                    Spacer()
                                    Text("\(formatQty(item.qty * Double(currentServings.wrappedValue))) \(item.unit)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: 16) {
                            DisclosureGroup(isExpanded: $showInstructions) {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                        HStack(alignment: .top, spacing: 14) {
                                            Text("\(index + 1)")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 30, height: 30)
                                                .background(AppTheme.primary)
                                                .clipShape(Circle())

                                            Text(step)
                                                .font(.subheadline)
                                                .foregroundStyle(AppTheme.text)

                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cooking steps")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(AppTheme.text)
                                    Text("\(recipe.steps.count) quick steps when you are ready to cook.")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }
                        }
                    }
                }
                .appScrollContentPadding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingOrder = true
            } label: {
                Label("Order ingredients", systemImage: "cart.fill")
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingOrder) {
            OrderCheckoutView(recipe: recipe, servings: currentServings.wrappedValue)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImageView(url: recipe.imageURL, cornerRadius: 28) {
                LinearGradient(
                    colors: [AppTheme.primary.opacity(0.18), AppTheme.accent.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(height: 320)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.18), location: 0.45),
                        .init(color: .black.opacity(0.68), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HeroTag(label: "Ready to cook", icon: "sparkles")
                    if recipe.macros.carbsG < 20 {
                        HeroTag(label: "Low carb", icon: "leaf.fill")
                    }
                }

                Text(recipe.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

                Text("Balanced for speed, macros, and checkout.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            }
            .padding(22)
        }
    }

    private var statsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader("Quick look", detail: "The numbers people actually care about before they commit.")

                HStack(spacing: 12) {
                    StatBadge(icon: "flame.fill", value: "\(recipe.calories)", label: "kcal", color: AppTheme.accent)
                    StatBadge(icon: "clock.fill", value: "\(recipe.prepTimeMin)", label: "min", color: .blue)
                    StatBadge(icon: "bolt.fill", value: "\(Int(recipe.macros.proteinG))g", label: "protein", color: AppTheme.primary)
                }
            }
        }
    }

    private func formatQty(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.text)

            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.mutedCard.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct HeroTag: View {
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.45))
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        }
        .clipShape(Capsule())
    }
}

private struct ServingsStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            stepperButton(systemImage: "minus", enabled: value > range.lowerBound) {
                if value > range.lowerBound { value -= 1 }
            }
            .accessibilityLabel("Decrease servings")

            Text("\(value)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()
                .frame(minWidth: 28)

            stepperButton(systemImage: "plus", enabled: value < range.upperBound) {
                if value < range.upperBound { value += 1 }
            }
            .accessibilityLabel("Increase servings")
        }
        .padding(.horizontal, 4)
        .background(AppTheme.mutedCard)
        .overlay {
            Capsule()
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value) servings")
    }

    private func stepperButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? AppTheme.primary : AppTheme.secondaryText.opacity(0.5))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
