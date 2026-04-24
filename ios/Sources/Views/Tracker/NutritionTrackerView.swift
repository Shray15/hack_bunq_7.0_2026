import SwiftUI

struct NutritionTrackerView: View {
    let consumedCal = 820
    let targetCal = 1800

    let protein = (consumed: 68.0, target: 150.0)
    let carbs = (consumed: 92.0, target: 200.0)
    let fat = (consumed: 28.0, target: 65.0)

    let mealLog: [(name: String, kcal: Int, url: URL?)] = [
        ("Overnight Oats", 380, URL(string: "https://images.unsplash.com/photo-1614961233913-a5113a4a34ed?w=200")),
        ("High-Protein Chicken Bowl", 540, URL(string: "https://images.unsplash.com/photo-1546793665-c74683f339c1?w=200")),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        AppCard {
                            VStack(alignment: .leading, spacing: 16) {
                                AppSectionHeader(
                                    "Today's nutrition",
                                    eyebrow: "Tracker",
                                    detail: "Kept simple for the hackathon: enough signal to show momentum and goal fit."
                                )

                                HStack(spacing: 18) {
                                    CalorieRingView(consumed: consumedCal, target: targetCal)
                                    VStack(spacing: 10) {
                                        MetricChip(title: "Protein", value: "\(Int(protein.consumed))/\(Int(protein.target)) g", icon: "bolt.fill", tint: .blue)
                                        MetricChip(title: "Carbs", value: "\(Int(carbs.consumed))/\(Int(carbs.target)) g", icon: "leaf.fill", tint: AppTheme.accent)
                                        MetricChip(title: "Fat", value: "\(Int(fat.consumed))/\(Int(fat.target)) g", icon: "drop.fill", tint: .purple)
                                    }
                                }
                            }
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 16) {
                                AppSectionHeader("Macro breakdown", detail: "Shift emphasis later based on the selected diet type.")

                                MacroBarRow(name: "Protein", consumed: protein.consumed, target: protein.target, color: .blue, unit: "g")
                                MacroBarRow(name: "Carbs", consumed: carbs.consumed, target: carbs.target, color: AppTheme.accent, unit: "g")
                                MacroBarRow(name: "Fat", consumed: fat.consumed, target: fat.target, color: .purple, unit: "g")
                            }
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 16) {
                                AppSectionHeader("Today's log", detail: "Meals ordered or planned through the app can populate this automatically.")

                                ForEach(mealLog, id: \.name) { meal in
                                    HStack(spacing: 14) {
                                        RemoteImageView(url: meal.url, cornerRadius: 18) {
                                            Color.secondary.opacity(0.12)
                                        }
                                        .frame(width: 64, height: 64)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(meal.name)
                                                .font(.headline)
                                                .foregroundStyle(AppTheme.text)
                                            Text("\(meal.kcal) kcal")
                                                .font(.subheadline)
                                                .foregroundStyle(AppTheme.secondaryText)
                                        }

                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationTitle("Nutrition")
        }
    }
}

struct CalorieRingView: View {
    let consumed: Int
    let target: Int

    private var progress: Double {
        min(Double(consumed) / Double(target), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.primary.opacity(0.12), lineWidth: 18)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.primary, AppTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text("\(consumed)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.text)
                Text("of \(target) kcal")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(width: 154, height: 154)
    }
}

struct MacroBarRow: View {
    let name: String
    let consumed: Double
    let target: Double
    let color: Color
    let unit: String

    private var progress: Double {
        min(consumed / target, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Text("\(Int(consumed))/\(Int(target)) \(unit)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color)
                        .frame(width: geo.size.width * progress, height: 12)
                }
            }
            .frame(height: 12)
        }
    }
}
