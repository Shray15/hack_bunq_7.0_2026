import Foundation

struct PlannedMeal: Identifiable, Hashable {
    var id: String { slot }
    let slot: String
    var recipe: Recipe?
    var title: String?
    var calories: Int
    var protein: Int = 0
    var carbs: Int = 0
    var fat: Int = 0
    var imageURL: URL?
    var loggedAt: Date?

    var isPlanned: Bool {
        recipe != nil || title != nil
    }

    var displayName: String {
        recipe?.name ?? title ?? "Plan this meal"
    }

    var displayImageURL: URL? {
        recipe?.imageURL ?? imageURL
    }
}
