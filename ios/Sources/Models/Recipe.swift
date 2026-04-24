import Foundation

struct Recipe: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let calories: Int
    let macros: Macros
    let ingredients: [Ingredient]
    let steps: [String]
    let imageURL: URL?
    let prepTimeMin: Int

    struct Macros: Codable, Hashable {
        let proteinG: Double
        let carbsG: Double
        let fatG: Double

        enum CodingKeys: String, CodingKey {
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, calories, macros, ingredients, steps
        case imageURL = "image_url"
        case prepTimeMin = "prep_time_min"
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
