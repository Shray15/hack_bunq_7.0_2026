import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @AppStorage("displayName") private var displayName = "Sai"

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        overviewCard

                        if let delivery = vm.upcomingDelivery {
                            DeliveryBanner(eta: delivery)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            AppSectionHeader(
                                "Today's meals",
                                eyebrow: "Daily brief",
                                detail: "A quick view of what is planned and what still needs a decision."
                            )

                            ForEach(vm.plannedMeals) { meal in
                                MealRow(meal: meal)
                            }
                        }

                        NutritionNudgeCard(weeklyProteinShort: vm.weeklyProteinShort)
                    }
                    .appScrollContentPadding()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var overviewCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        AppTag(Date.now.formatted(.dateTime.weekday(.wide)), color: AppTheme.primary, icon: "sun.max.fill")

                        Text("Good morning, \(displayName)")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(AppTheme.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Dinner is still open. You can close the day with one strong meal and keep groceries moving.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

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
                    .frame(width: 58, height: 58)
                    .shadow(color: AppTheme.primary.opacity(0.18), radius: 14, y: 8)
                }

                CalorieProgressCard(consumed: vm.consumedCalories, target: vm.dailyCalorieTarget)

                HStack(spacing: 12) {
                    MetricChip(
                        title: "Weekly gap",
                        value: "\(vm.weeklyProteinShort) g",
                        icon: "bolt.heart.fill",
                        tint: .blue
                    )
                    MetricChip(
                        title: "Next action",
                        value: "Plan dinner",
                        icon: "fork.knife.circle.fill",
                        tint: AppTheme.accent
                    )
                }

                HStack(spacing: 10) {
                    StatusStrip(
                        icon: "figure.walk.motion",
                        tint: AppTheme.primary,
                        title: "Today",
                        value: "1 meal left to plan"
                    )

                    StatusStrip(
                        icon: "cart.fill",
                        tint: .blue,
                        title: "Basket",
                        value: "Ready when dinner is set"
                    )
                }
            }
        }
    }
}

struct CalorieProgressCard: View {
    let consumed: Int
    let target: Int

    private var progress: Double {
        min(Double(consumed) / Double(target), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily target")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.secondaryText)
                        .textCase(.uppercase)
                    Text("\(consumed) / \(target) kcal")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.text)
                }
                Spacer()
                AppTag("\(Int(progress * 100))% used", color: AppTheme.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.primary.opacity(0.10))
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.primary, AppTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 24), height: 14)
                }
            }
            .frame(height: 14)
        }
        .padding(16)
        .background(AppTheme.mutedCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct DeliveryBanner: View {
    let eta: Date

    var body: some View {
        AppCard(padding: 14, background: Color(red: 0.90, green: 0.97, blue: 0.93)) {
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
}

struct MealRow: View {
    let meal: PlannedMeal

    var body: some View {
        AppCard(background: meal.recipe == nil ? Color(red: 0.95, green: 0.98, blue: 0.96) : AppTheme.card) {
            HStack(spacing: 14) {
                RemoteImageView(url: meal.recipe?.imageURL, cornerRadius: 20) {
                    ZStack {
                        LinearGradient(
                            colors: [AppTheme.primary.opacity(0.18), AppTheme.accent.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: meal.recipe == nil ? "sparkles" : "fork.knife")
                            .font(.title3)
                            .foregroundStyle(AppTheme.primaryDeep.opacity(0.65))
                    }
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 8) {
                    AppTag(meal.slot, color: AppTheme.primary)

                    Text(meal.recipe?.name ?? "Plan this meal")
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)

                    Text(meal.recipe == nil ? "Add a dinner that fits your target and pantry." : "\(meal.calories) kcal")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                if meal.recipe == nil {
                    Text("Plan")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }
}

struct StatusStrip: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.mutedCard.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct NutritionNudgeCard: View {
    let weeklyProteinShort: Int

    var body: some View {
        AppCard(background: AppTheme.mutedCard) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nutrition nudge")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("\(weeklyProteinShort) g short on protein this week")
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text("A strong dinner tonight closes the gap quickly.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
