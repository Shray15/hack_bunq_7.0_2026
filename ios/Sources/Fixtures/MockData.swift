import Foundation

// Hardcoded fixtures — Person A works against these until backend is deployed (H0–H6).
// Flip APIService.useMockData = false once the real API is live.
enum MockData {

    static let recipes: [Recipe] = [
        Recipe(
            id: "recipe-1",
            name: "High-Protein Chicken Bowl",
            macros: .init(calories: 540, proteinG: 45, carbsG: 40, fatG: 18),
            ingredients: [
                .init(name: "chicken breast",  qty: 200, unit: "g"),
                .init(name: "brown rice",       qty: 80,  unit: "g"),
                .init(name: "broccoli",         qty: 150, unit: "g"),
                .init(name: "olive oil",        qty: 15,  unit: "ml"),
                .init(name: "garlic",           qty: 2,   unit: "cloves"),
            ],
            steps: [
                "Season chicken with salt, pepper, and garlic powder.",
                "Heat olive oil over medium-high heat.",
                "Cook chicken 6–7 min per side until golden.",
                "Cook brown rice per package instructions.",
                "Steam broccoli 5 min until tender-crisp.",
                "Slice chicken and serve over rice with broccoli.",
            ],
            imageURL: URL(string: "https://images.unsplash.com/photo-1546793665-c74683f339c1?w=800"),
            prepTimeMin: 25
        ),
        Recipe(
            id: "recipe-2",
            name: "Keto Salmon with Avocado",
            macros: .init(calories: 480, proteinG: 38, carbsG: 6, fatG: 34),
            ingredients: [
                .init(name: "salmon fillet", qty: 180, unit: "g"),
                .init(name: "avocado",        qty: 1,   unit: "whole"),
                .init(name: "lemon",          qty: 1,   unit: "whole"),
                .init(name: "capers",         qty: 20,  unit: "g"),
                .init(name: "butter",         qty: 15,  unit: "g"),
            ],
            steps: [
                "Pat salmon dry, season with salt and pepper.",
                "Melt butter in a skillet over medium-high heat.",
                "Cook salmon skin-side up 4 min, flip, 3 more min.",
                "Halve and slice the avocado.",
                "Plate salmon with avocado, capers, and a squeeze of lemon.",
            ],
            imageURL: URL(string: "https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=800"),
            prepTimeMin: 15
        ),
        Recipe(
            id: "recipe-3",
            name: "Vegan Buddha Bowl",
            macros: .init(calories: 420, proteinG: 18, carbsG: 58, fatG: 14),
            ingredients: [
                .init(name: "chickpeas",       qty: 200, unit: "g"),
                .init(name: "quinoa",          qty: 80,  unit: "g"),
                .init(name: "kale",            qty: 100, unit: "g"),
                .init(name: "tahini",          qty: 30,  unit: "g"),
                .init(name: "cherry tomatoes", qty: 100, unit: "g"),
            ],
            steps: [
                "Cook quinoa in 160 ml water for 12 min.",
                "Roast chickpeas at 200 °C with paprika for 20 min.",
                "Massage kale with a pinch of salt.",
                "Whisk tahini with lemon juice and water.",
                "Assemble: quinoa base, kale, chickpeas, tomatoes, drizzle dressing.",
            ],
            imageURL: URL(string: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=800"),
            prepTimeMin: 30
        ),
        Recipe(
            id: "recipe-4",
            name: "Turkey Chili Meal Prep",
            macros: .init(calories: 510, proteinG: 48, carbsG: 46, fatG: 14),
            ingredients: [
                .init(name: "lean turkey mince", qty: 200, unit: "g"),
                .init(name: "kidney beans", qty: 120, unit: "g"),
                .init(name: "crushed tomatoes", qty: 200, unit: "g"),
                .init(name: "bell pepper", qty: 1, unit: "whole"),
                .init(name: "brown rice", qty: 70, unit: "g"),
            ],
            steps: [
                "Brown turkey mince in a deep pan with chili powder and cumin.",
                "Add diced pepper, crushed tomatoes, and beans.",
                "Simmer for 20 min until thick.",
                "Cook brown rice separately.",
                "Portion chili over rice for a high-protein meal prep bowl.",
            ],
            imageURL: URL(string: "https://images.unsplash.com/photo-1574894709920-11b28e7367e3?w=800"),
            prepTimeMin: 35
        ),
        Recipe(
            id: "recipe-5",
            name: "Greek Yogurt Power Oats",
            macros: .init(calories: 430, proteinG: 36, carbsG: 52, fatG: 9),
            ingredients: [
                .init(name: "rolled oats", qty: 60, unit: "g"),
                .init(name: "greek yogurt", qty: 200, unit: "g"),
                .init(name: "berries", qty: 120, unit: "g"),
                .init(name: "chia seeds", qty: 10, unit: "g"),
                .init(name: "whey protein", qty: 20, unit: "g"),
            ],
            steps: [
                "Stir oats, yogurt, chia seeds, and protein powder together.",
                "Add a splash of water until creamy.",
                "Top with berries.",
                "Chill for at least 2 hours or overnight.",
            ],
            imageURL: URL(string: "https://images.unsplash.com/photo-1517673132405-a56a62b18caf?w=800"),
            prepTimeMin: 10
        ),
        Recipe(
            id: "recipe-6",
            name: "Tuna Whole-Grain Wrap",
            macros: .init(calories: 390, proteinG: 34, carbsG: 38, fatG: 11),
            ingredients: [
                .init(name: "tuna in water", qty: 140, unit: "g"),
                .init(name: "whole-grain wrap", qty: 1, unit: "whole"),
                .init(name: "greek yogurt", qty: 40, unit: "g"),
                .init(name: "spinach", qty: 60, unit: "g"),
                .init(name: "cucumber", qty: 80, unit: "g"),
            ],
            steps: [
                "Mix tuna with yogurt, pepper, lemon, and a pinch of salt.",
                "Layer spinach and cucumber on the wrap.",
                "Add tuna mix and roll tightly.",
                "Toast in a dry pan for 2 min per side if preferred.",
            ],
            imageURL: URL(string: "https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=800"),
            prepTimeMin: 8
        ),
        Recipe(
            id: "recipe-7",
            name: "Tofu Edamame Stir Fry",
            macros: .init(calories: 460, proteinG: 32, carbsG: 44, fatG: 18),
            ingredients: [
                .init(name: "firm tofu", qty: 180, unit: "g"),
                .init(name: "edamame", qty: 100, unit: "g"),
                .init(name: "mixed vegetables", qty: 180, unit: "g"),
                .init(name: "soba noodles", qty: 70, unit: "g"),
                .init(name: "soy ginger sauce", qty: 35, unit: "ml"),
            ],
            steps: [
                "Press tofu dry and cube it.",
                "Sear tofu in a hot pan until crisp on the edges.",
                "Add vegetables and edamame, then stir fry for 5 min.",
                "Toss with cooked soba noodles and soy ginger sauce.",
            ],
            imageURL: URL(string: "https://images.unsplash.com/photo-1512058564366-18510be2db19?w=800"),
            prepTimeMin: 20
        ),
        Recipe(
            id: "recipe-8",
            name: "Egg White Frittata Plate",
            macros: .init(calories: 360, proteinG: 34, carbsG: 24, fatG: 12),
            ingredients: [
                .init(name: "egg whites", qty: 220, unit: "ml"),
                .init(name: "whole egg", qty: 1, unit: "whole"),
                .init(name: "spinach", qty: 80, unit: "g"),
                .init(name: "mushrooms", qty: 100, unit: "g"),
                .init(name: "sweet potato", qty: 140, unit: "g"),
            ],
            steps: [
                "Roast cubed sweet potato until tender.",
                "Saute mushrooms and spinach in a nonstick pan.",
                "Whisk egg whites with one whole egg and pour over vegetables.",
                "Cook covered until set, then serve with the sweet potato.",
            ],
            imageURL: URL(string: "https://images.unsplash.com/photo-1525351484163-7529414344d8?w=800"),
            prepTimeMin: 18
        ),
    ]

    /// Pick a mock recipe whose vibe matches the transcript so demo prompts feel
    /// responsive even before a real LLM is wired up.
    static func pickRecipe(for transcript: String) -> Recipe {
        let prompt = transcript.lowercased()
        let scored = recipes.map { recipe -> (Recipe, Int) in
            let haystack = ([recipe.name] + recipe.ingredients.map(\.name)).joined(separator: " ").lowercased()
            var score = 0
            for keyword in keywordsByCategory.keys where prompt.contains(keyword) {
                if let category = keywordsByCategory[keyword] {
                    if haystack.contains(category) { score += 3 }
                }
            }
            for word in prompt.split(whereSeparator: { !$0.isLetter }) where word.count > 3 {
                if haystack.contains(word.lowercased()) { score += 1 }
            }
            return (recipe, score)
        }
        let best = scored.max { $0.1 < $1.1 }
        return best?.1 == 0 ? recipes.randomElement() ?? recipes[0] : best?.0 ?? recipes[0]
    }

    private static let keywordsByCategory: [String: String] = [
        "keto":      "keto",
        "vegan":     "vegan",
        "vegetarian":"vegan",
        "salmon":    "salmon",
        "fish":      "salmon",
        "tuna":      "tuna",
        "turkey":    "turkey",
        "chili":     "chili",
        "tofu":      "tofu",
        "stir":      "tofu",
        "oats":      "oats",
        "yogurt":    "yogurt",
        "breakfast": "oats",
        "protein":   "protein",
        "chicken":   "chicken",
        "rice":      "rice",
        "egg":       "egg",
        "frittata":  "egg",
    ]

    // MARK: - Cart fixtures (match new wire contracts)

    static let comparisonResponse = CartComparisonResponse(
        cartId: "cart-mock-1",
        recipeId: "recipe-1",
        comparison: [
            StoreComparison(store: "ah",     totalEur: 13.45, itemCount: 5, missingCount: 0),
            StoreComparison(store: "picnic", totalEur: 14.55, itemCount: 4, missingCount: 1),
        ]
    )

    static let ahItemsResponse = CartItemsResponse(
        cartId: "cart-mock-1",
        selectedStore: "ah",
        totalEur: 13.45,
        items: [
            CartItem(
                productId: "ah-7421",
                ingredient: "chicken breast",
                productName: "AH Kipfilet 500 g",
                imageURL: URL(string: "https://images.unsplash.com/photo-1604503468506-a8da13d82791?w=240"),
                qty: 1,
                unit: "500 g",
                priceEur: 5.49
            ),
            CartItem(
                productId: "ah-3120",
                ingredient: "brown rice",
                productName: "AH Zilvervliesrijst 1 kg",
                imageURL: URL(string: "https://images.unsplash.com/photo-1586201375761-83865001e31c?w=240"),
                qty: 1,
                unit: "1 kg",
                priceEur: 1.89
            ),
            CartItem(
                productId: "ah-5530",
                ingredient: "broccoli",
                productName: "AH Broccoli 400 g",
                imageURL: URL(string: "https://images.unsplash.com/photo-1459411552884-841db9b3cc2a?w=240"),
                qty: 1,
                unit: "400 g",
                priceEur: 1.29
            ),
            CartItem(
                productId: "ah-2210",
                ingredient: "olive oil",
                productName: "AH Extra Vierge Olijfolie 500 ml",
                imageURL: URL(string: "https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?w=240"),
                qty: 1,
                unit: "500 ml",
                priceEur: 3.99
            ),
            CartItem(
                productId: "ah-1180",
                ingredient: "garlic",
                productName: "AH Knoflook 3-pack",
                imageURL: URL(string: "https://images.unsplash.com/photo-1471194402529-8e0f5a675de6?w=240"),
                qty: 1,
                unit: "3 pack",
                priceEur: 0.79
            ),
        ]
    )

    static let picnicItemsResponse = CartItemsResponse(
        cartId: "cart-mock-1",
        selectedStore: "picnic",
        totalEur: 14.55,
        items: [
            CartItem(
                productId: "pc-44012",
                ingredient: "chicken breast",
                productName: "Picnic Kipfilet vers 500 g",
                imageURL: URL(string: "https://images.unsplash.com/photo-1604503468506-a8da13d82791?w=240"),
                qty: 1,
                unit: "500 g",
                priceEur: 5.99
            ),
            CartItem(
                productId: "pc-22301",
                ingredient: "brown rice",
                productName: "Picnic Bruine rijst 1 kg",
                imageURL: URL(string: "https://images.unsplash.com/photo-1586201375761-83865001e31c?w=240"),
                qty: 1,
                unit: "1 kg",
                priceEur: 1.79
            ),
            CartItem(
                productId: "pc-55510",
                ingredient: "broccoli",
                productName: "Picnic Broccoli 500 g",
                imageURL: URL(string: "https://images.unsplash.com/photo-1459411552884-841db9b3cc2a?w=240"),
                qty: 1,
                unit: "500 g",
                priceEur: 1.49
            ),
            CartItem(
                productId: "pc-22020",
                ingredient: "olive oil",
                productName: "Picnic Olijfolie extra vierge 500 ml",
                imageURL: URL(string: "https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?w=240"),
                qty: 1,
                unit: "500 ml",
                priceEur: 4.29
            ),
        ]
    )

    static func itemsResponse(for store: String?) -> CartItemsResponse {
        switch store?.lowercased() {
        case "picnic": return picnicItemsResponse
        default:       return ahItemsResponse
        }
    }

    static let checkoutResponse = CheckoutResponse(
        orderId: "order-mock-1",
        paymentURL: "https://bunq.me/HackBunqDemo/13.45/Groceries",
        amountEur: 13.45
    )
}
