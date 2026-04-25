import SwiftUI

struct NutritionTrackerView: View {
    @AppStorage("calorieTarget") private var targetCal = 2000

    private let consumedCal = 920

    private let macros: [MacroMetric] = [
        .init(name: "Protein", consumed: 68, target: 150, unit: "g", icon: "bolt.fill", color: .blue),
        .init(name: "Carbs", consumed: 92, target: 200, unit: "g", icon: "leaf.fill", color: AppTheme.primary),
        .init(name: "Fat", consumed: 28, target: 65, unit: "g", icon: "drop.fill", color: .purple),
    ]

    private let mealLog: [MealLogEntry] = [
        .init(
            name: "Overnight Oats",
            time: "08:10",
            kcal: 380,
            protein: 23,
            url: URL(string: "https://images.unsplash.com/photo-1614961233913-a5113a4a34ed?w=300")
        ),
        .init(
            name: "High-Protein Chicken Bowl",
            time: "12:35",
            kcal: 540,
            protein: 45,
            url: URL(string: "https://images.unsplash.com/photo-1546793665-c74683f339c1?w=300")
        ),
    ]

    private var remainingCalories: Int {
        max(targetCal - consumedCal, 0)
    }

    private var calorieProgress: Double {
        guard targetCal > 0 else { return 0 }
        return min(Double(consumedCal) / Double(targetCal), 1)
    }

    private var weeklyCalories: [WeekCalorieEntry] {
        [
            .init(day: "Mon", kcal: 1660, status: .onTrack),
            .init(day: "Tue", kcal: 1825, status: .onTrack),
            .init(day: "Wed", kcal: 2110, status: .over),
            .init(day: "Thu", kcal: 1740, status: .onTrack),
            .init(day: "Fri", kcal: consumedCal, status: .today),
            .init(day: "Sat", kcal: nil, status: .upcoming),
            .init(day: "Sun", kcal: nil, status: .upcoming),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        calorieDashboard
                        macroCard
                        weeklyCard
                        insightCard
                        mealLogCard
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationTitle("Track")
            .navigationBarTitleDisplayMode(.inline)
        }
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

            AppTag("On track", color: AppTheme.success, icon: "checkmark.circle.fill")
                .padding(.top, 4)
        }
    }

    private var calorieDashboard: some View {
        VStack(spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    calorieRing
                    calorieStats
                }

                VStack(spacing: 16) {
                    calorieRing
                    calorieStats
                }
            }

            HStack(spacing: 10) {
                ForEach(macros) { macro in
                    CompactMacroPill(macro: macro)
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            AppTheme.mutedCard.opacity(0.95),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 1)
        }
        .shadow(color: AppTheme.primaryDeep.opacity(0.10), radius: 24, y: 14)
    }

    private var calorieRing: some View {
        CalorieRingView(
            consumed: consumedCal,
            target: targetCal,
            progress: calorieProgress
        )
    }

    private var calorieStats: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardStat(
                title: "Remaining",
                value: "\(remainingCalories)",
                suffix: "kcal",
                icon: "flame.fill",
                tint: AppTheme.accent
            )

            DashboardStat(
                title: "Logged meals",
                value: "\(mealLog.count)",
                suffix: "today",
                icon: "fork.knife",
                tint: AppTheme.primary
            )
        }
    }

    private var macroCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Macro balance", action: "Goal fit")

                ForEach(macros) { macro in
                    MacroBarRow(macro: macro)
                }
            }
        }
    }

    private var weeklyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "This week", action: "3 of 4 on track")
                WeeklyCalorieChart(entries: weeklyCalories, target: targetCal)
            }
        }
    }

    private var insightCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "target")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(AppTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Dinner can do the heavy lifting")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Text("Add a high-protein dinner around 700 kcal to land near your daily target without pushing carbs too high.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppTheme.primary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var mealLogCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Today's log", action: "+ Add")

                VStack(spacing: 12) {
                    ForEach(mealLog) { meal in
                        MealLogRow(meal: meal)
                    }
                }
            }
        }
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

private struct MealLogEntry: Identifiable {
    let id = UUID()
    let name: String
    let time: String
    let kcal: Int
    let protein: Int
    let url: URL?
}

private struct WeekCalorieEntry: Identifiable {
    enum Status {
        case onTrack
        case over
        case today
        case upcoming
    }

    let id = UUID()
    let day: String
    let kcal: Int?
    let status: Status
}

private struct CalorieRingView: View {
    private let consumed: Int
    private let target: Int
    private let progress: Double

    init(consumed: Int, target: Int, progress: Double) {
        self.consumed = consumed
        self.target = target
        self.progress = progress
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
                .shadow(color: AppTheme.primary.opacity(0.22), radius: 10, y: 6)

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
        .frame(width: 158, height: 158)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(consumed) of \(target) kilocalories")
    }
}

private struct DashboardStat: View {
    private let title: String
    private let value: String
    private let suffix: String
    private let icon: String
    private let tint: Color

    init(title: String, value: String, suffix: String, icon: String, tint: Color) {
        self.title = title
        self.value = value
        self.suffix = suffix
        self.icon = icon
        self.tint = tint
    }

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
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CompactMacroPill: View {
    private let macro: MacroMetric

    init(macro: MacroMetric) {
        self.macro = macro
    }

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
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SectionTitle: View {
    private let title: String
    private let action: String

    init(title: String, action: String) {
        self.title = title
        self.action = action
    }

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

private struct MacroBarRow: View {
    private let macro: MacroMetric

    init(macro: MacroMetric) {
        self.macro = macro
    }

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
    }
}

private struct WeeklyCalorieChart: View {
    private let entries: [WeekCalorieEntry]
    private let target: Int

    init(entries: [WeekCalorieEntry], target: Int) {
        self.entries = entries
        self.target = target
    }

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
                                .fill(color(for: entry.status))
                                .frame(height: height(for: entry))
                                .opacity(entry.status == .upcoming ? 0.25 : 1)
                        }
                        .frame(maxWidth: .infinity)

                        Text(entry.day)
                            .font(.caption2.weight(entry.status == .today ? .bold : .semibold))
                            .foregroundStyle(entry.status == .today ? AppTheme.text : AppTheme.secondaryText)
                    }
                }
            }

            HStack {
                Label("Target \(target) kcal", systemImage: "scope")
                Spacer()
                Text("Avg 1,651 kcal")
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

    private func color(for status: WeekCalorieEntry.Status) -> Color {
        switch status {
        case .onTrack:
            return AppTheme.success
        case .over:
            return AppTheme.accent
        case .today:
            return AppTheme.primaryDeep
        case .upcoming:
            return AppTheme.primary
        }
    }
}

private struct MealLogRow: View {
    private let meal: MealLogEntry

    init(meal: MealLogEntry) {
        self.meal = meal
    }

    var body: some View {
        HStack(spacing: 14) {
            RemoteImageView(url: meal.url, cornerRadius: 16) {
                AppTheme.mutedCard
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(meal.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(meal.time, systemImage: "clock")
                    Text("\(meal.protein)g protein")
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 8)

            Text("\(meal.kcal)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()
                .overlay(alignment: .bottomTrailing) {
                    Text("kcal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .offset(y: 13)
                }
                .padding(.bottom, 8)
        }
        .padding(10)
        .background(AppTheme.mutedCard.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
