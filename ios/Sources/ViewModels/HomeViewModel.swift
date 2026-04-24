import Foundation

struct PlannedMeal: Identifiable {
    let id    = UUID()
    let slot:     String  // "Breakfast" | "Lunch" | "Dinner"
    let recipe:   Recipe?
    let calories: Int
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var plannedMeals:       [PlannedMeal] = []
    @Published var consumedCalories:   Int           = 820
    @Published var dailyCalorieTarget: Int           = 1800
    @Published var weeklyProteinShort: Int           = 300   // grams below weekly goal
    @Published var upcomingDelivery:   Date?         = nil

    init() { loadMock() }

    private func loadMock() {
        plannedMeals = [
            PlannedMeal(slot: "Breakfast", recipe: nil,                    calories: 380),
            PlannedMeal(slot: "Lunch",     recipe: MockData.recipes.first, calories: 540),
            PlannedMeal(slot: "Dinner",    recipe: nil,                    calories: 0),
        ]
        upcomingDelivery = Calendar.current.date(byAdding: .hour, value: 3, to: Date())
    }
}
