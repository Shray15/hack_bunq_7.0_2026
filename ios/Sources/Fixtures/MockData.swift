import Foundation

// Hardcoded fixtures — Person A works against these until backend is deployed (H0–H6).
// Flip APIService.useMockData = false once the real API is live.
enum MockData {

    static let recipes: [Recipe] = [
        Recipe(
            id: "recipe-1",
            name: "High-Protein Chicken Bowl",
            calories: 540,
            macros: .init(proteinG: 45, carbsG: 40, fatG: 18),
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
            calories: 480,
            macros: .init(proteinG: 38, carbsG: 6, fatG: 34),
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
            calories: 420,
            macros: .init(proteinG: 18, carbsG: 58, fatG: 14),
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
    ]

    static let cartResponse = CartResponse(
        items: [
            CartItem(id: "ah_001", ingredient: "chicken breast",  productName: "AH Kipfilet 500 g",               priceEur: 5.49, qty: 1, store: "ah"),
            CartItem(id: "ah_002", ingredient: "brown rice",       productName: "AH Zilvervliesrijst 1 kg",        priceEur: 1.89, qty: 1, store: "ah"),
            CartItem(id: "ah_003", ingredient: "broccoli",         productName: "AH Broccoli 400 g",               priceEur: 1.29, qty: 1, store: "ah"),
            CartItem(id: "ah_004", ingredient: "olive oil",        productName: "AH Extra Vierge Olijfolie 500 ml",priceEur: 3.99, qty: 1, store: "ah"),
            CartItem(id: "ah_005", ingredient: "garlic",           productName: "AH Knoflook 3-pack",              priceEur: 0.79, qty: 1, store: "ah"),
        ],
        totalEur: 13.45,
        store: "ah"
    )

    static let checkoutResponse = CheckoutResponse(
        paymentURL: "bunq://request/demo-payment-123",
        amountEur: 13.45
    )
}
