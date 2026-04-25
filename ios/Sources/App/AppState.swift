import Foundation
import Combine

struct DayKcal: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let kcal: Int?
}

@MainActor
final class AppState: ObservableObject {
    @Published var displayName: String = "Sai"
    @Published var dietType: DietType = .balanced
    @Published var householdSize: Int = 1
    @Published var bunqConnected: Bool = false
    @Published var dailyCalorieTarget: Int = 1800
    @Published var plannedMeals: [PlannedMeal] = []
    @Published var weeklyHistory: [DayKcal] = []
    @Published var upcomingDelivery: Date?
    @Published var planningPrefill: String?
    @Published var pendingMealSlot: String?

    init() { loadMock() }

    func userProfile() -> UserProfile {
        UserProfile(
            dietType: dietType,
            dailyCalorieTarget: dailyCalorieTarget,
            householdSize: householdSize,
            bunqConnected: bunqConnected
        )
    }

    private var loggedMeals: [PlannedMeal] {
        plannedMeals.filter(\.isPlanned)
    }

    var mealLog: [PlannedMeal] {
        loggedMeals.sorted {
            ($0.loggedAt ?? .distantPast) > ($1.loggedAt ?? .distantPast)
        }
    }

    var consumedCalories: Int {
        loggedMeals.reduce(0) { $0 + $1.calories }
    }

    var consumedProtein: Int {
        loggedMeals.reduce(0) { $0 + $1.protein }
    }

    var consumedCarbs: Int {
        loggedMeals.reduce(0) { $0 + $1.carbs }
    }

    var consumedFat: Int {
        loggedMeals.reduce(0) { $0 + $1.fat }
    }

    var remainingCalories: Int {
        max(dailyCalorieTarget - consumedCalories, 0)
    }

    var macroTargets: (protein: Int, carbs: Int, fat: Int) {
        switch dietType {
        case .highProtein:
            return (protein: 170, carbs: 180, fat: 65)
        case .keto:
            return (protein: 140, carbs: 35, fat: 120)
        case .vegan:
            return (protein: 115, carbs: 230, fat: 70)
        default:
            return (protein: 150, carbs: 200, fat: 65)
        }
    }

    func requestPlanning(for slot: String) {
        pendingMealSlot = slot
        planningPrefill = planningBrief(for: slot)
    }

    func consumePlanningPrefill() -> String? {
        let prefill = planningPrefill
        planningPrefill = nil
        return prefill
    }

    func addMeal(
        name: String,
        kcal: Int,
        protein: Int,
        carbs: Int = 0,
        fat: Int = 0,
        time: Date = Date(),
        imageURL: URL? = nil
    ) {
        logMeal(
            name: name,
            kcal: kcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            time: time,
            imageURL: imageURL
        )
    }

    func removeMeal(id: String) {
        clearSlot(id)
    }

    /// Manually log a meal. Slot is inferred from `time` (Breakfast/Lunch/Dinner).
    func logMeal(
        name: String,
        kcal: Int,
        protein: Int,
        carbs: Int = 0,
        fat: Int = 0,
        time: Date = Date(),
        imageURL: URL? = nil
    ) {
        let slot = slot(for: time)
        upsertPlannedMeal(
            slot: slot,
            recipe: nil,
            title: name,
            calories: kcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            imageURL: imageURL,
            loggedAt: time
        )
    }

    func clearSlot(_ slot: String) {
        upsertPlannedMeal(
            slot: slot,
            recipe: nil,
            title: nil,
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            imageURL: nil,
            loggedAt: nil
        )
    }

    func completeOrder(recipe: Recipe, servings: Int) {
        let slot = pendingMealSlot ?? firstOpenMealSlot ?? "Dinner"
        upsertPlannedMeal(
            slot: slot,
            recipe: recipe,
            title: nil,
            calories: recipe.calories,
            protein: Int(recipe.macros.proteinG),
            carbs: Int(recipe.macros.carbsG),
            fat: Int(recipe.macros.fatG),
            imageURL: recipe.imageURL,
            loggedAt: Date()
        )
        upcomingDelivery = Calendar.current.date(byAdding: .hour, value: 3, to: Date())
        pendingMealSlot = nil
    }

    private func loadMock() {
        let calendar = Calendar.current
        let now = Date()
        let breakfast = calendar.date(bySettingHour: 8, minute: 10, second: 0, of: now) ?? now
        let lunch = calendar.date(bySettingHour: 12, minute: 35, second: 0, of: now) ?? now

        plannedMeals = [
            PlannedMeal(
                slot: "Breakfast",
                recipe: nil,
                title: "Overnight Oats",
                calories: 380,
                protein: 23,
                carbs: 52,
                fat: 10,
                imageURL: URL(string: "https://images.unsplash.com/photo-1614961233913-a5113a4a34ed?w=300"),
                loggedAt: breakfast
            ),
            PlannedMeal(
                slot: "Lunch",
                recipe: MockData.recipes.first,
                title: nil,
                calories: MockData.recipes.first?.calories ?? 540,
                protein: Int(MockData.recipes.first?.macros.proteinG ?? 45),
                carbs: Int(MockData.recipes.first?.macros.carbsG ?? 40),
                fat: Int(MockData.recipes.first?.macros.fatG ?? 18),
                imageURL: MockData.recipes.first?.imageURL,
                loggedAt: lunch
            ),
            PlannedMeal(
                slot: "Dinner",
                recipe: nil,
                title: nil,
                calories: 0,
                imageURL: nil,
                loggedAt: nil
            ),
        ]
        upcomingDelivery = nil
        weeklyHistory = generateMockHistory(today: now, calendar: calendar)
    }

    private func generateMockHistory(today: Date, calendar: Calendar) -> [DayKcal] {
        var entries: [DayKcal] = []
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return entries
        }
        let mockKcal = [1660, 1825, 2110, 1740, 0, 0, 0]
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) else {
                continue
            }
            if calendar.isDate(date, inSameDayAs: today) {
                entries.append(DayKcal(date: date, kcal: nil))
            } else if date < today {
                entries.append(DayKcal(date: date, kcal: mockKcal[offset]))
            } else {
                entries.append(DayKcal(date: date, kcal: nil))
            }
        }
        return entries
    }

    private var firstOpenMealSlot: String? {
        plannedMeals.first { !$0.isPlanned }?.slot
    }

    private func planningBrief(for slot: String) -> String {
        let people = householdSize == 1 ? "one person" : "\(householdSize) people"
        let remaining = max(remainingCalories, 450)
        return "Plan \(slot.lowercased()) for \(people), \(dietType.rawValue.lowercased()), around \(remaining) calories, with enough protein."
    }

    private func slot(for time: Date) -> String {
        switch Calendar.current.component(.hour, from: time) {
        case 5..<11:  return "Breakfast"
        case 11..<16: return "Lunch"
        default:      return "Dinner"
        }
    }

    private func upsertPlannedMeal(
        slot: String,
        recipe: Recipe?,
        title: String?,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        imageURL: URL?,
        loggedAt: Date?
    ) {
        let updated = PlannedMeal(
            slot: slot,
            recipe: recipe,
            title: title,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            imageURL: imageURL,
            loggedAt: loggedAt
        )
        if let index = plannedMeals.firstIndex(where: { $0.slot == slot }) {
            plannedMeals[index] = updated
        } else {
            plannedMeals.append(updated)
        }
    }
}
