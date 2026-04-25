import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var health: HealthKitService
    @State private var selectedRecipe: Recipe?
    @State private var showDeliveryDetails = false
    @State private var showMealCardSetup = false
    @State private var pushMealCardScreen = false

    private var displayName: String { appState.displayName }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heroCard

                        MealCardTile(
                            card: appState.currentMealCard,
                            isLoading: appState.mealCardLoading && appState.currentMealCard == nil,
                            onSetup: { showMealCardSetup = true },
                            onOpen: { pushMealCardScreen = true }
                        )

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

                        RightNowCard(
                            suggestion: rightNowSuggestion,
                            primaryAction: handleRightNowAction
                        )

                        MacrosStrip(
                            protein: macroProgress(consumed: appState.consumedProtein, target: appState.macroTargets.protein),
                            carbs: macroProgress(consumed: appState.consumedCarbs, target: appState.macroTargets.carbs),
                            fat: macroProgress(consumed: appState.consumedFat, target: appState.macroTargets.fat)
                        )
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $pushMealCardScreen) {
                MealCardScreen()
            }
            .task {
                await appState.refreshMealCard()
            }
            .refreshable {
                await appState.refreshMealCard()
            }
            .sheet(item: $selectedRecipe) { recipe in
                NavigationStack {
                    RecipeDetailView(recipe: recipe)
                }
            }
            .sheet(isPresented: $showMealCardSetup) {
                MealCardSetupView()
                    .environmentObject(appState)
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

    // MARK: - Right-now suggestion

    /// Reads the current context (post-workout window, time of day, remaining
    /// calories, planned meals) and returns the most useful single suggestion.
    /// Drives the home-screen hero card so the demo always shows a smart,
    /// timely action instead of three half-empty meal slots.
    private var rightNowSuggestion: RightNowSuggestion {
        let unplanned = appState.plannedMeals.filter { !$0.isPlanned }
        let remaining = max(appState.remainingCalories, 0)

        // Post-workout always wins — a fresh workout has the most actionable
        // and demo-friendly framing.
        if appState.isPostWorkoutWindow {
            return RightNowSuggestion(
                eyebrow: "Right now",
                title: "Refuel from your workout",
                body: "Aim for 35–45 g protein in the next hour. We'll cap calories around \(max(remaining, 500)).",
                cta: "Plan a refuel meal",
                action: .planSlot(unplanned.first?.slot ?? slotForCurrentTime),
                accentIcon: "bolt.fill"
            )
        }

        // Everything planned, all macros tracked — celebrate.
        if unplanned.isEmpty {
            return RightNowSuggestion(
                eyebrow: "Today",
                title: "Day is locked in",
                body: "All meals planned and groceries on the way. Add water or log a snack from the Track tab.",
                cta: "Open Track",
                action: .openTracker,
                accentIcon: "checkmark.seal.fill"
            )
        }

        // Pick the most relevant unplanned slot.
        let target = unplanned.first { $0.slot.lowercased() == slotForCurrentTime.lowercased() }
            ?? unplanned.first!
        let lower = target.slot.lowercased()

        return RightNowSuggestion(
            eyebrow: "Right now",
            title: "Time for \(lower)",
            body: "About \(remaining) kcal left today. We'll fit it in your macros.",
            cta: "Plan \(lower)",
            action: .planSlot(target.slot),
            accentIcon: "sparkles"
        )
    }

    private var slotForCurrentTime: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11:  return "Breakfast"
        case 11..<16: return "Lunch"
        default:      return "Dinner"
        }
    }

    private func handleRightNowAction(_ action: RightNowAction) {
        switch action {
        case .planSlot(let slot):
            appState.requestPlanning(for: slot)
            selectedTab = 1
        case .openTracker:
            selectedTab = 3
        }
    }

    private func macroProgress(consumed: Int, target: Int) -> MacroProgress {
        MacroProgress(
            consumed: consumed,
            target: max(target, 1),
            remaining: max(target - consumed, 0)
        )
    }
}

// MARK: - Right-now suggestion model

enum RightNowAction {
    case planSlot(String)
    case openTracker
}

struct RightNowSuggestion {
    let eyebrow: String
    let title: String
    let body: String
    let cta: String
    let action: RightNowAction
    let accentIcon: String
}

struct RightNowCard: View {
    let suggestion: RightNowSuggestion
    let primaryAction: (RightNowAction) -> Void

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.primary, AppTheme.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: suggestion.accentIcon)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: AppTheme.primary.opacity(0.28), radius: 10, y: 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.eyebrow)
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(AppTheme.primary)
                        Text(suggestion.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Text(suggestion.body)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    primaryAction(suggestion.action)
                } label: {
                    Label(suggestion.cta, systemImage: "sparkles")
                }
                .buttonStyle(AppPrimaryButtonStyle())
            }
        }
    }
}

// MARK: - Macros strip

struct MacroProgress {
    let consumed: Int
    let target: Int
    let remaining: Int

    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(Double(consumed) / Double(target), 1)
    }
}

struct MacrosStrip: View {
    let protein: MacroProgress
    let carbs: MacroProgress
    let fat: MacroProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Macros today")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: 10) {
                HomeMacroChip(label: "Protein", unit: "g", progress: protein, tint: AppTheme.primary)
                HomeMacroChip(label: "Carbs", unit: "g", progress: carbs, tint: AppTheme.accent)
                HomeMacroChip(label: "Fat", unit: "g", progress: fat, tint: AppTheme.success)
            }
        }
    }
}

struct HomeMacroChip: View {
    let label: String
    let unit: String
    let progress: MacroProgress
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            Text("\(progress.consumed)\(unit)")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.14))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(geo.size.width * progress.fraction, 6))
                }
            }
            .frame(height: 6)

            Text("\(progress.remaining)\(unit) left")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: tint.opacity(0.10), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(progress.consumed) of \(progress.target) \(unit), \(progress.remaining) left")
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
