import Foundation

enum DietType: String, CaseIterable, Codable {
    case balanced    = "Balanced"
    case highProtein = "High-Protein"
    case keto        = "Keto"
    case paleo       = "Paleo"
    case vegan       = "Vegan"
    case custom      = "Custom"
}

enum BiologicalSex: String, CaseIterable, Codable {
    case male
    case female

    var label: String {
        switch self {
        case .male:   return "Male"
        case .female: return "Female"
        }
    }
}

enum NutritionGoal: String, CaseIterable, Codable, Identifiable {
    case cut
    case maintain
    case bulk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cut:      return "Cut"
        case .maintain: return "Maintain"
        case .bulk:     return "Bulk"
        }
    }

    var detail: String {
        switch self {
        case .cut:      return "Lose fat"
        case .maintain: return "Hold weight"
        case .bulk:     return "Build muscle"
        }
    }

    /// Multiplier applied to TDEE to produce daily calorie target.
    var calorieMultiplier: Double {
        switch self {
        case .cut:      return 0.80
        case .maintain: return 1.00
        case .bulk:     return 1.10
        }
    }

    /// Protein target per kg of bodyweight.
    var proteinPerKg: Double {
        switch self {
        case .cut:      return 2.2
        case .maintain: return 1.8
        case .bulk:     return 2.0
        }
    }

    var icon: String {
        switch self {
        case .cut:      return "arrow.down.right"
        case .maintain: return "equal"
        case .bulk:     return "arrow.up.right"
        }
    }
}

enum ActivityLevel: String, CaseIterable, Codable, Identifiable {
    case sedentary
    case light
    case moderate
    case heavy
    case athlete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light:     return "Light"
        case .moderate:  return "Moderate"
        case .heavy:     return "Heavy"
        case .athlete:   return "Athlete"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: return "Desk job, no training"
        case .light:     return "1–2 sessions/week"
        case .moderate:  return "3–4 sessions/week"
        case .heavy:     return "5–6 sessions/week"
        case .athlete:   return "Daily training + active job"
        }
    }

    /// Mifflin-St Jeor activity multiplier.
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light:     return 1.375
        case .moderate:  return 1.55
        case .heavy:     return 1.725
        case .athlete:   return 1.9
        }
    }
}

struct UserProfile: Codable {
    var dietType: DietType       = .balanced
    var dailyCalorieTarget: Int  = 2000
    var proteinTargetG: Double   = 150
    var carbTargetG: Double      = 200
    var fatTargetG: Double       = 65
    var householdSize: Int       = 1
    var bodyweightKg: Double     = 70
    var heightCm: Double         = 175
    var age: Int                 = 30
    var biologicalSex: BiologicalSex = .male
    var goal: NutritionGoal      = .maintain
    var activityLevel: ActivityLevel = .moderate
}

struct WeightEntry: Identifiable, Codable, Hashable {
    var id: String { dateKey }
    let date: Date
    let weightKg: Double

    /// Yyyy-MM-dd key so two logs on the same day collapse.
    var dateKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Mifflin-St Jeor BMR estimator.
enum NutritionMath {
    static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: BiologicalSex) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male:   return base + 5
        case .female: return base - 161
        }
    }

    static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.multiplier
    }

    static func calorieTarget(tdee: Double, goal: NutritionGoal) -> Int {
        Int((tdee * goal.calorieMultiplier).rounded())
    }

    /// Returns macro grams for the given calorie + bodyweight + goal.
    static func macroGrams(
        calories: Int,
        bodyweightKg: Double,
        goal: NutritionGoal
    ) -> (protein: Int, carbs: Int, fat: Int) {
        let proteinG = bodyweightKg * goal.proteinPerKg
        let fatG = max(bodyweightKg * 0.8, 50)              // hormonal floor
        let proteinKcal = proteinG * 4
        let fatKcal = fatG * 9
        let carbKcal = max(Double(calories) - proteinKcal - fatKcal, 0)
        let carbsG = carbKcal / 4
        return (Int(proteinG.rounded()), Int(carbsG.rounded()), Int(fatG.rounded()))
    }

    /// Daily water target in ml. 35 ml × kg, clamped to a humane range.
    static func waterTargetMl(weightKg: Double) -> Int {
        let ml = weightKg * 35
        return min(max(Int(ml.rounded()), 1500), 4500)
    }
}
