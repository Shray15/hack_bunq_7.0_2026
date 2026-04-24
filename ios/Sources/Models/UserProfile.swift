import Foundation

enum DietType: String, CaseIterable, Codable {
    case balanced    = "Balanced"
    case highProtein = "High-Protein"
    case keto        = "Keto"
    case paleo       = "Paleo"
    case vegan       = "Vegan"
    case custom      = "Custom"
}

struct UserProfile: Codable {
    var dietType: DietType       = .balanced
    var dailyCalorieTarget: Int  = 2000
    var proteinTargetG: Double   = 150
    var carbTargetG: Double      = 200
    var fatTargetG: Double       = 65
    var allergies: [String]      = []
    var householdSize: Int       = 1
    var bunqConnected: Bool      = false
}
