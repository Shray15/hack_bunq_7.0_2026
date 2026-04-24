import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe
    @State private var servings = 1
    @State private var showingOrder = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero

                        statsCard

                        AppCard {
                            VStack(alignment: .leading, spacing: 16) {
                                AppSectionHeader("Ingredients", detail: "Scaled live for the number of people you are cooking for.")

                                HStack {
                                    Text("Servings")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Stepper("\(servings)", value: $servings, in: 1...12)
                                        .labelsHidden()
                                    Text("\(servings)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.primaryDeep)
                                        .frame(minWidth: 24)
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
                                        Text("\(formatQty(item.qty * Double(servings))) \(item.unit)")
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
                                AppSectionHeader("Instructions", detail: "Built for a quick weeknight cook, not a three-page blog recipe.")

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
                        }
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.text)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.card)
                            .clipShape(Circle())
                    }
                }
            }
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
                OrderCheckoutView(recipe: recipe, servings: servings)
            }
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
                    colors: [.clear, .black.opacity(0.52)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    AppTag("Ready to cook", color: .white, icon: "sparkles")
                    if recipe.macros.carbsG < 20 {
                        AppTag("Low carb", color: .white, icon: "leaf.fill")
                    }
                }

                Text(recipe.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text("Balanced for speed, macros, and a clean grocery handoff into checkout.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
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
