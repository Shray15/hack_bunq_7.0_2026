import SwiftUI

struct NutritionTrackerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var health: HealthKitService
    @State private var showLogMeal = false
    @State private var showLogWeight = false

    private var macros: [MacroMetric] {
        let targets = appState.macroTargets
        return [
            MacroMetric(
                name: "Protein",
                consumed: Double(appState.consumedProtein),
                target: Double(targets.protein),
                unit: "g",
                icon: "bolt.fill",
                color: .blue
            ),
            MacroMetric(
                name: "Carbs",
                consumed: Double(appState.consumedCarbs),
                target: Double(targets.carbs),
                unit: "g",
                icon: "leaf.fill",
                color: AppTheme.primary
            ),
            MacroMetric(
                name: "Fat",
                consumed: Double(appState.consumedFat),
                target: Double(targets.fat),
                unit: "g",
                icon: "drop.fill",
                color: .purple
            ),
        ]
    }

    private var loggedMeals: [PlannedMeal] {
        appState.plannedMeals.filter(\.isPlanned)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        calorieDashboard
                        waterCard
                        macroCard
                        bodyweightCard
                        weeklyCard
                        mealLogCard
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationTitle("Track")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLogMeal) {
                LogMealSheet { name, kcal, protein, carbs, fat in
                    appState.logMeal(
                        name: name,
                        kcal: kcal,
                        protein: protein,
                        carbs: carbs,
                        fat: fat
                    )
                }
            }
            .sheet(isPresented: $showLogWeight) {
                LogWeightSheet(initialWeight: appState.bodyweightKg) { kg in
                    appState.logWeight(kg)
                }
                .presentationDetents([.fraction(0.42), .medium])
            }
        }
    }

    // MARK: - Water

    private var waterCard: some View {
        let total = appState.waterTodayMl
        let target = appState.waterTargetMl
        let glassMl = max(target / 8, 200)
        let filledGlasses = min(total / glassMl, 8)

        return AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hydration")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.text)
                        Text("\(total) / \(target) ml today")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .monospacedDigit()
                    }
                    Spacer()
                    Button {
                        appState.resetWaterToday()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.mutedCard)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset today's water")
                }

                HStack(spacing: 8) {
                    ForEach(0..<8, id: \.self) { idx in
                        Button {
                            if idx < filledGlasses {
                                // Tapping a filled glass below the current count empties it.
                                let target = (idx) * glassMl
                                appState.addWater(ml: target - total)
                            } else {
                                appState.addWater(ml: glassMl)
                            }
                        } label: {
                            Image(systemName: idx < filledGlasses ? "drop.fill" : "drop")
                                .font(.title3)
                                .foregroundStyle(idx < filledGlasses ? Color.blue : AppTheme.secondaryText.opacity(0.5))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(idx < filledGlasses ? Color.blue.opacity(0.10) : AppTheme.mutedCard.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Glass \(idx + 1)")
                    }
                }
            }
        }
    }

    // MARK: - Bodyweight

    private var bodyweightCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body weight")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.text)
                        if let latest = appState.latestWeightEntry {
                            HStack(spacing: 6) {
                                Text("\(formatKg(latest.weightKg)) kg")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                                    .monospacedDigit()
                                if let delta = appState.weightDelta7d, abs(delta) >= 0.05 {
                                    deltaPill(delta: delta)
                                }
                            }
                        } else {
                            Text("No log yet")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    Spacer()
                    Button {
                        showLogWeight = true
                    } label: {
                        Label("Log", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log weight")
                }

                WeightTrendChart(entries: appState.recentWeightLog)
                    .frame(height: 80)

                HStack {
                    Text("Goal: \(appState.goal.label) · Target \(formatKcal(appState.dailyCalorieTarget)) kcal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    if appState.recentWeightLog.count >= 2 {
                        Text("\(appState.recentWeightLog.count) day window")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
        }
    }

    private func deltaPill(delta: Double) -> some View {
        let goalAlignsWithDelta: Bool
        switch appState.goal {
        case .cut:      goalAlignsWithDelta = delta < 0
        case .bulk:     goalAlignsWithDelta = delta > 0
        case .maintain: goalAlignsWithDelta = abs(delta) < 0.4
        }
        let color: Color = goalAlignsWithDelta ? AppTheme.success : AppTheme.accent
        let symbol = delta >= 0 ? "arrow.up" : "arrow.down"
        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
            Text(String(format: "%.1f kg / 7d", abs(delta)))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func formatKg(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    private func formatKcal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nutrition")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 12)

            AppTag(statusLabel, color: statusColor, icon: statusIcon)
                .padding(.top, 4)
        }
    }

    private var calorieDashboard: some View {
        AppCard {
            VStack(spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 18) {
                        CalorieRing(
                            consumed: appState.consumedCalories,
                            target: appState.dailyCalorieTarget
                        )
                        calorieStats
                    }

                    VStack(spacing: 16) {
                        CalorieRing(
                            consumed: appState.consumedCalories,
                            target: appState.dailyCalorieTarget
                        )
                        calorieStats
                    }
                }

                HStack(spacing: 10) {
                    ForEach(macros) { macro in
                        CompactMacroPill(macro: macro)
                    }
                }
            }
        }
    }

    private var calorieStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardStat(
                title: "Remaining",
                value: "\(appState.remainingCalories)",
                suffix: "kcal",
                icon: "flame.fill",
                tint: AppTheme.accent
            )
            DashboardStat(
                title: "Logged meals",
                value: "\(loggedMeals.count)",
                suffix: "today",
                icon: "fork.knife",
                tint: AppTheme.primary
            )
        }
    }

    private var macroCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Macro balance", action: appState.dietType.rawValue)

                ForEach(macros) { macro in
                    MacroBarRow(macro: macro)
                }
            }
        }
    }

    private var weeklyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "This week", action: weeklySummary)
                WeeklyCalorieChart(
                    entries: weeklyEntries,
                    target: appState.dailyCalorieTarget
                )
            }
        }
    }

    private var mealLogCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Today's meals")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                    Spacer()
                    Button {
                        showLogMeal = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.primary.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log a meal")
                }

                if loggedMeals.isEmpty {
                    EmptyMealLogView {
                        showLogMeal = true
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(loggedMeals) { meal in
                            MealLogRow(meal: meal)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        appState.clearSlot(meal.slot)
                                    } label: {
                                        Label("Clear", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private var statusLabel: String {
        appState.consumedCalories <= appState.dailyCalorieTarget ? "On track" : "Over target"
    }

    private var statusIcon: String {
        appState.consumedCalories <= appState.dailyCalorieTarget ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var statusColor: Color {
        appState.consumedCalories <= appState.dailyCalorieTarget ? AppTheme.success : AppTheme.accent
    }

    private var weeklyEntries: [WeekCalorieEntry] {
        let calendar = Calendar.current
        return appState.weeklyHistory.map { day in
            let kcal = calendar.isDateInToday(day.date) ? appState.consumedCalories : day.kcal
            return WeekCalorieEntry(date: day.date, kcal: kcal)
        }
    }

    private var weeklySummary: String {
        let finishedDays = weeklyEntries.filter { $0.kcal != nil }
        let onTrackDays = finishedDays.filter { ($0.kcal ?? 0) <= appState.dailyCalorieTarget }.count
        return "\(onTrackDays) of \(finishedDays.count) on track"
    }
}

private struct MacroMetric: Identifiable {
    let id = UUID()
    let name: String
    let consumed: Double
    let target: Double
    let unit: String
    let icon: String
    let color: Color

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(consumed / target, 1)
    }
}

private struct WeekCalorieEntry: Identifiable {
    var id: Date { date }
    let date: Date
    let kcal: Int?
}

private struct SectionTitle: View {
    let title: String
    let action: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.text)
            Spacer()
            Text(action)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.primary.opacity(0.10))
                .clipShape(Capsule())
        }
    }
}

private struct CalorieRing: View {
    let consumed: Int
    let target: Int

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(consumed) / Double(target), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.primaryDeep.opacity(0.08), lineWidth: 16)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.primary, AppTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: AppTheme.primary.opacity(0.20), radius: 10, y: 6)

            VStack(spacing: 3) {
                Text("\(consumed)")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.text)
                    .monospacedDigit()
                Text("/ \(target) kcal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(width: 156, height: 156)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(consumed) of \(target) kilocalories")
    }
}

private struct DashboardStat: View {
    let title: String
    let value: String
    let suffix: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .monospacedDigit()
                    Text(suffix)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.mutedCard.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CompactMacroPill: View {
    let macro: MacroMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: macro.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(macro.color)
                .frame(width: 28, height: 28)
                .background(macro.color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(macro.name)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Text("\(Int(macro.consumed))\(macro.unit)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.mutedCard.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MacroBarRow: View {
    let macro: MacroMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(macro.name, systemImage: macro.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Text("\(Int(macro.consumed)) / \(Int(macro.target)) \(macro.unit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(macro.color.opacity(0.10))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [macro.color, macro.color.opacity(0.68)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * macro.progress, 14))
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(macro.name): \(Int(macro.consumed)) of \(Int(macro.target)) \(macro.unit)")
    }
}

private struct WeeklyCalorieChart: View {
    let entries: [WeekCalorieEntry]
    let target: Int

    private var maxValue: Double {
        max(Double(target), Double(entries.compactMap(\.kcal).max() ?? target)) * 1.08
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(entries) { entry in
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.primaryDeep.opacity(0.06))
                                .frame(height: 88)

                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(color(for: entry))
                                .frame(height: height(for: entry))
                                .opacity(entry.kcal == nil ? 0.24 : 1)
                        }
                        .frame(maxWidth: .infinity)

                        Text(entry.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(Calendar.current.isDateInToday(entry.date) ? .bold : .semibold))
                            .foregroundStyle(Calendar.current.isDateInToday(entry.date) ? AppTheme.text : AppTheme.secondaryText)
                    }
                }
            }

            HStack {
                Label("Target \(target) kcal", systemImage: "scope")
                Spacer()
                Text("Today \(entries.first(where: { Calendar.current.isDateInToday($0.date) })?.kcal ?? 0) kcal")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly calorie chart")
    }

    private func height(for entry: WeekCalorieEntry) -> CGFloat {
        guard let kcal = entry.kcal else { return 5 }
        return max(CGFloat(Double(kcal) / maxValue) * 88, 8)
    }

    private func color(for entry: WeekCalorieEntry) -> Color {
        guard let kcal = entry.kcal else { return AppTheme.primary }
        if Calendar.current.isDateInToday(entry.date) {
            return AppTheme.primaryDeep
        }
        return kcal <= target ? AppTheme.success : AppTheme.accent
    }
}

private struct MealLogRow: View {
    let meal: PlannedMeal

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 14) {
            RemoteImageView(url: meal.displayImageURL, cornerRadius: 16) {
                ZStack {
                    AppTheme.mutedCard
                    Image(systemName: "fork.knife")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(meal.slot.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.primary)
                    if let loggedAt = meal.loggedAt {
                        Text("· \(Self.timeFormatter.string(from: loggedAt))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Text(meal.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)

                Text("\(meal.protein)g protein")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(meal.calories)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .monospacedDigit()
                Text("kcal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(10)
        .background(AppTheme.mutedCard.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meal.displayName), \(meal.calories) kilocalories, \(meal.protein) grams protein")
    }
}

private struct EmptyMealLogView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife")
                .font(.title2)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 52, height: 52)
                .background(AppTheme.primary.opacity(0.10))
                .clipShape(Circle())

            Text("Nothing logged yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.text)

            Text("Add a meal to start tracking calories and macros for today.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onAdd()
            } label: {
                Label("Log a meal", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct LogMealSheet: View {
    var onSave: (_ name: String, _ kcal: Int, _ protein: Int, _ carbs: Int, _ fat: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(kcalText) != nil &&
        (Int(kcalText) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.sentences)
                }
                Section("Nutrition") {
                    TextField("Calories", text: $kcalText)
                        .keyboardType(.numberPad)
                    TextField("Protein (g)", text: $proteinText)
                        .keyboardType(.numberPad)
                    TextField("Carbs (g)", text: $carbsText)
                        .keyboardType(.numberPad)
                    TextField("Fat (g)", text: $fatText)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Log a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            Int(kcalText) ?? 0,
                            Int(proteinText) ?? 0,
                            Int(carbsText) ?? 0,
                            Int(fatText) ?? 0
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Weight trend chart

private struct WeightTrendChart: View {
    let entries: [WeightEntry]

    private var minWeight: Double {
        entries.map(\.weightKg).min() ?? 0
    }

    private var maxWeight: Double {
        entries.map(\.weightKg).max() ?? 1
    }

    private var range: Double {
        max(maxWeight - minWeight, 0.5)
    }

    var body: some View {
        if entries.count < 2 {
            placeholder
        } else {
            GeometryReader { geo in
                let height = geo.size.height
                let width = geo.size.width
                let stepX = width / CGFloat(max(entries.count - 1, 1))

                ZStack(alignment: .topLeading) {
                    Path { path in
                        for (index, entry) in entries.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = yPos(for: entry.weightKg, in: height)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(AppTheme.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    Path { path in
                        for (index, entry) in entries.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = yPos(for: entry.weightKg, in: height)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.addLine(to: CGPoint(x: 0, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.primary.opacity(0.25), AppTheme.primary.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    if let last = entries.last {
                        let lastX = CGFloat(entries.count - 1) * stepX
                        let lastY = yPos(for: last.weightKg, in: height)
                        Circle()
                            .fill(AppTheme.primary)
                            .frame(width: 8, height: 8)
                            .position(x: lastX, y: lastY)
                    }
                }
            }
        }
    }

    private func yPos(for weight: Double, in height: CGFloat) -> CGFloat {
        let normalized = (weight - minWeight) / range
        let inverted = 1 - normalized
        return CGFloat(inverted) * (height - 8) + 4
    }

    private var placeholder: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(AppTheme.primary.opacity(0.6))
            Text("Log a few days to see your trend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Log weight sheet

private struct LogWeightSheet: View {
    let initialWeight: Double
    var onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double

    init(initialWeight: Double, onSave: @escaping (Double) -> Void) {
        self.initialWeight = initialWeight
        self.onSave = onSave
        _weight = State(initialValue: initialWeight)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 22) {
                    Spacer(minLength: 20)

                    Text("Log today's weight")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.text)

                    Text(String(format: "%.1f kg", weight))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryDeep)
                        .monospacedDigit()

                    Slider(value: $weight, in: 35...200, step: 0.1)
                        .tint(AppTheme.primary)
                        .padding(.horizontal, 20)

                    HStack(spacing: 12) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.secondaryText.opacity(0.4)))

                        Button("Save") {
                            onSave(weight)
                            dismiss()
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 10)
                }
            }
            .navigationTitle("Weight log")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
