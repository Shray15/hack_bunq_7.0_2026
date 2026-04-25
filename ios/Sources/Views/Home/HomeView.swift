import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var health: HealthKitService
    @State private var selectedRecipe: Recipe?
    @State private var showDeliveryDetails = false

    private var displayName: String { appState.displayName }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heroCard

                        if appState.isPostWorkoutWindow, let endedAt = appState.lastWorkoutEndedAt {
                            PostWorkoutBanner(endedAt: endedAt) {
                                selectedTab = 1
                            }
                        }

                        if let delivery = appState.upcomingDelivery {
                            DeliveryBanner(eta: delivery) {
                                showDeliveryDetails = true
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            AppSectionHeader(
                                "Today's meals",
                                eyebrow: "Daily brief"
                            )

                            ForEach(appState.plannedMeals) { meal in
                                MealRow(meal: meal) {
                                    handleMealTap(meal)
                                }
                            }
                        }

                        Button {
                            selectedTab = 1
                        } label: {
                            Label("Plan a meal", systemImage: "sparkles")
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .accessibilityLabel("Plan a meal with the assistant")
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedRecipe) { recipe in
                NavigationStack {
                    RecipeDetailView(recipe: recipe)
                }
            }
            .alert("Delivery on the way", isPresented: $showDeliveryDetails) {
                Button("OK", role: .cancel) {}
            } message: {
                if let eta = appState.upcomingDelivery {
                    Text("Arriving \(eta.formatted(date: .omitted, time: .shortened)). We'll notify you when it's nearby.")
                }
            }
        }
    }

    private var heroCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(greetingPrefix), \(displayName)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppTheme.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(heroBodyCopy)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button {
                        selectedTab = 4
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.primary, AppTheme.primaryDeep],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Text(String(displayName.prefix(1)).uppercased())
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                        .frame(width: 56, height: 56)
                        .shadow(color: AppTheme.primary.opacity(0.18), radius: 14, y: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open profile")
                }

                CalorieProgressCard(consumed: appState.consumedCalories, target: appState.dailyCalorieTarget)
            }
        }
    }

    // MARK: - Derived copy

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hello"
        }
    }

    private var heroBodyCopy: String {
        let unplanned = appState.plannedMeals.filter { !$0.isPlanned }
        guard !unplanned.isEmpty else {
            return "All meals planned. Groceries are queued — nice work."
        }
        let slots = unplanned.map { $0.slot.lowercased() }
        let joined: String
        switch slots.count {
        case 1:  joined = slots[0]
        case 2:  joined = "\(slots[0]) and \(slots[1])"
        default: joined = slots.dropLast().joined(separator: ", ") + ", and " + (slots.last ?? "")
        }
        let sentence = joined.prefix(1).uppercased() + joined.dropFirst()
        return "\(sentence) still open. Plan now to keep groceries moving."
    }

    private var navigationTitleText: String {
        Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Actions

    private func handleMealTap(_ meal: PlannedMeal) {
        if let recipe = meal.recipe {
            selectedRecipe = recipe
        } else if meal.isPlanned {
            selectedTab = 3
        } else {
            appState.requestPlanning(for: meal.slot)
            selectedTab = 1
        }
    }
}

// MARK: - Calorie progress

struct CalorieProgressCard: View {
    let consumed: Int
    let target: Int

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(consumed) / Double(target), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(consumed) / \(target) kcal")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.text)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.primary.opacity(0.10))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.primary, AppTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 20), height: 12)
                }
            }
            .frame(height: 12)
        }
        .padding(16)
        .background(AppTheme.mutedCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(consumed) of \(target) kilocalories, \(Int(progress * 100)) percent")
    }
}

// MARK: - Delivery banner

// MARK: - Post-workout banner

struct PostWorkoutBanner: View {
    let endedAt: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppCard(padding: 14, background: AppTheme.softPanel) {
                HStack(spacing: 14) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Post-workout window")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post-workout window. Tap to plan a high-protein meal.")
    }

    private var subtitle: String {
        let minutes = max(Int(Date().timeIntervalSince(endedAt) / 60), 0)
        return "Workout finished \(minutes) min ago — let's plan a 40g protein meal."
    }
}

struct DeliveryBanner: View {
    let eta: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppCard(padding: 14, background: AppTheme.success.opacity(0.10)) {
                HStack(spacing: 14) {
                    Image(systemName: "shippingbox.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.success.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Delivery arriving today")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        Text(eta, style: .relative)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delivery arriving today. Tap for details.")
    }
}

// MARK: - Meal row

struct MealRow: View {
    let meal: PlannedMeal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppCard(background: meal.recipe == nil ? AppTheme.mutedCard.opacity(0.6) : AppTheme.card) {
                HStack(spacing: 14) {
                    RemoteImageView(url: meal.displayImageURL, cornerRadius: 20) {
                        ZStack {
                            LinearGradient(
                                colors: [AppTheme.primary.opacity(0.18), AppTheme.accent.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: meal.isPlanned ? "fork.knife" : "sparkles")
                                .font(.title3)
                                .foregroundStyle(AppTheme.primaryDeep.opacity(0.65))
                        }
                    }
                    .frame(width: 84, height: 84)

                    VStack(alignment: .leading, spacing: 8) {
                        AppTag(meal.slot, color: AppTheme.primary)

                        Text(meal.displayName)
                            .font(.headline)
                            .foregroundStyle(AppTheme.text)
                            .multilineTextAlignment(.leading)

                        Text(mealSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    if !meal.isPlanned {
                        Text("Plan")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.primary.opacity(0.12))
                            .clipShape(Capsule())
                    } else if meal.recipe != nil {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var mealSubtitle: String {
        if !meal.isPlanned {
            return "Fits your remaining target and profile."
        }
        if meal.recipe == nil {
            return "Logged · \(meal.calories) kcal"
        }
        return "\(meal.calories) kcal"
    }

    private var accessibilityLabel: String {
        if let recipe = meal.recipe {
            return "\(meal.slot): \(recipe.name), \(meal.calories) kilocalories. Tap to open."
        } else if meal.isPlanned {
            return "\(meal.slot): \(meal.displayName), \(meal.calories) kilocalories. Tap to view tracker."
        } else {
            return "\(meal.slot) is unplanned. Tap to plan a meal."
        }
    }
}
