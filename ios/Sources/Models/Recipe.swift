import Foundation

struct Recipe: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let macros: Macros
    let ingredients: [Ingredient]
    let steps: [String]
    let imageURL: URL?
    let prepTimeMin: Int

    struct Macros: Codable, Hashable {
        let calories: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int

        enum CodingKeys: String, CodingKey {
            case calories
            case proteinG = "protein_g"
            case carbsG   = "carbs_g"
            case fatG     = "fat_g"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, macros, ingredients, steps
        case imageURL    = "image_url"
        case prepTimeMin = "prep_time_min"
    }
}

extension Recipe {
    /// Convenience for legacy call sites — sourced from `macros.calories`.
    var calories: Int { macros.calories }

    /// Returns a copy with the image URL replaced. Used when an `image_ready`
    /// SSE event upgrades a placeholder recipe to its rendered Nano Banana image.
    func replacing(imageURL: URL?) -> Recipe {
        Recipe(
            id: id,
            name: name,
            macros: macros,
            ingredients: ingredients,
            steps: steps,
            imageURL: imageURL,
            prepTimeMin: prepTimeMin
        )
    }
}

/// Wire shape of `POST /chat` 202 response.
struct ChatAccepted: Codable, Hashable {
    let chatId: String
    let accepted: Bool

    enum CodingKeys: String, CodingKey {
        case chatId = "chat_id"
        case accepted
    }
}

struct Ingredient: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let qty: Double
    let unit: String

    init(name: String, qty: Double, unit: String) {
        self.id = UUID()
        self.name = name
        self.qty = qty
        self.unit = unit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.qty = try c.decode(Double.self, forKey: .qty)
        self.unit = try c.decode(String.self, forKey: .unit)
    }

    enum CodingKeys: String, CodingKey { case name, qty, unit }
}
