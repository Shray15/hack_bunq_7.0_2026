import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case network(Error)
    case server(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid URL"
        case .unauthorized:     return "You need to sign in again."
        case .network(let e):   return e.localizedDescription
        case .server(let code): return "Server error \(code)"
        case .decoding(let e):  return "Decode error: \(e.localizedDescription)"
        }
    }
}

// Toggle useMockData → false once backend is reachable.
// Update baseURL to the EC2 deployment IP per frontend_implementation.md.
class APIService {
    static let shared = APIService()
    private init() {}

    var baseURL = "http://107.20.41.184:4568"
    var useMockData = false

    /// Every Codable in the project declares explicit snake_case CodingKeys, so
    /// keyDecodingStrategy stays at the default. Combining .convertFromSnakeCase
    /// with explicit keys causes every decode to fail because the strategy
    /// converts JSON keys to camelCase BEFORE matching CodingKey raw values.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Auth helpers

    /// Loads the current bearer token from the keychain on every call so we always
    /// see the freshest value (login/logout don't have to update a cached copy here).
    private var bearer: String? {
        KeychainStore.read(AuthService.keychainAccount)
    }

    /// Builds a request with the JSON content type and `Authorization: Bearer <jwt>` header
    /// when a token is present.
    private func authedRequest(url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bearer {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// Centralised response handler that maps HTTP status codes to APIError, with
    /// a special path for 401 so AuthService can boot the user back to the login screen.
    private func handle(_ data: Data, _ response: URLResponse) async throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            return data
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            await AuthService.shared.handleUnauthorized()
            throw APIError.unauthorized
        default:
            throw APIError.server(http.statusCode)
        }
    }

    // MARK: - Auth

    /// `POST /auth/signup`
    func signup(email: String, password: String) async throws -> AuthResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 400_000_000)
            return AuthResponse(accessToken: "mock-jwt-\(UUID().uuidString.prefix(8))", tokenType: "bearer")
        }
        return try await postAuth(path: "/auth/signup", email: email, password: password)
    }

    /// `POST /auth/login`
    func login(email: String, password: String) async throws -> AuthResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 400_000_000)
            return AuthResponse(accessToken: "mock-jwt-\(UUID().uuidString.prefix(8))", tokenType: "bearer")
        }
        return try await postAuth(path: "/auth/login", email: email, password: password)
    }

    // MARK: - Profile

    /// `GET /user/profile`
    func getProfile() async throws -> BackendUserProfile {
        if useMockData {
            try await Task.sleep(nanoseconds: 250_000_000)
            return BackendUserProfile(
                diet: "balanced",
                allergies: [],
                dailyCalorieTarget: 2000,
                proteinGTarget: 150,
                carbsGTarget: 200,
                fatGTarget: 65,
                storePriority: ["ah", "picnic"]
            )
        }

        guard let url = URL(string: "\(baseURL)/user/profile") else { throw APIError.invalidURL }
        let req = authedRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(BackendUserProfile.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    /// `PATCH /user/profile` — sends only the fields you want to change.
    @discardableResult
    func patchProfile(_ profile: BackendUserProfile) async throws -> BackendUserProfile {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            return profile
        }

        guard let url = URL(string: "\(baseURL)/user/profile") else { throw APIError.invalidURL }
        var req = authedRequest(url: url, method: "PATCH")

        // CodingKeys already encode to snake_case; default key strategy keeps them as-is.
        req.httpBody = try JSONEncoder().encode(profile)

        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(BackendUserProfile.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    // MARK: - Auth helpers (private)

    private func postAuth(path: String, email: String, password: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.server(http.statusCode)
        }
        do { return try decoder.decode(AuthResponse.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    // MARK: - Chat

    /// `POST /chat` — returns 202 immediately. The recipe arrives later as a
    /// `recipe_complete` SSE event on the realtime channel.
    func postChat(transcript: String) async throws -> ChatAccepted {
        if useMockData {
            return await mockPostChat(transcript: transcript)
        }

        guard let url = URL(string: "\(baseURL)/chat") else { throw APIError.invalidURL }
        var req = authedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["transcript": transcript])

        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(ChatAccepted.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    /// In mock mode, schedule a simulated `recipe_complete` (and a delayed
    /// `image_ready`) on the realtime channel so the chat view exercises the
    /// real SSE-driven flow without a backend.
    private func mockPostChat(transcript: String) async -> ChatAccepted {
        try? await Task.sleep(nanoseconds: 250_000_000)
        let chatId = UUID().uuidString
        let baseRecipe = MockData.pickRecipe(for: transcript)
        let pendingImage = baseRecipe.replacing(imageURL: nil)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            RealtimeService.shared.simulate(.recipeComplete(RecipeCompleteEvent(
                chatId: chatId,
                recipeId: baseRecipe.id,
                recipe: pendingImage
            )))

            if let url = baseRecipe.imageURL {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                RealtimeService.shared.simulate(.imageReady(ImageReadyEvent(
                    recipeId: baseRecipe.id,
                    imageURL: url.absoluteString
                )))
            }
        }

        return ChatAccepted(chatId: chatId, accepted: true)
    }

    // MARK: - Cart (new 2-step flow)

    /// `POST /cart/from-recipe` — returns store totals only, no items yet.
    func compareStores(recipeId: String, people: Int) async throws -> CartComparisonResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            return MockData.comparisonResponse
        }

        guard let url = URL(string: "\(baseURL)/cart/from-recipe") else { throw APIError.invalidURL }

        var req = authedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "recipe_id": recipeId,
            "people": people,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(CartComparisonResponse.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    /// `POST /cart/{cart_id}/select-store` — returns the item list with images.
    func selectStore(cartId: String, store: String) async throws -> CartItemsResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 400_000_000)
            return MockData.itemsResponse(for: store)
        }

        guard let url = URL(string: "\(baseURL)/cart/\(cartId)/select-store") else { throw APIError.invalidURL }

        var req = authedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["store": store])

        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(CartItemsResponse.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    /// `PATCH /cart/{cart_id}/items/{item_id}` — flip `removed_at` so the
    /// backend's eventual checkout (and Picnic cart commit) reflects the user's
    /// actual basket selection. `removed: true` skips the item; `false` puts it
    /// back. Idempotent on the backend.
    func setItemRemoved(cartId: String, itemId: String, removed: Bool) async throws {
        if useMockData { return }

        guard let url = URL(string: "\(baseURL)/cart/\(cartId)/items/\(itemId)") else {
            throw APIError.invalidURL
        }

        var req = authedRequest(url: url, method: "PATCH")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["removed": removed])

        let (data, response) = try await URLSession.shared.data(for: req)
        _ = try await handle(data, response)
    }

    /// `POST /cart/{cart_id}/commit` — push the cart's current active items
    /// into the real grocery cart (Picnic only; AH has no programmatic
    /// write). Idempotent: the backend clears the real cart before re-adding,
    /// so calling this every Add-to-cart tap keeps picnic.app in sync.
    @discardableResult
    func commitCart(cartId: String) async throws -> CartItemsResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            return MockData.itemsResponse(for: "picnic")
        }

        guard let url = URL(string: "\(baseURL)/cart/\(cartId)/commit") else {
            throw APIError.invalidURL
        }
        let req = authedRequest(url: url, method: "POST")

        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(CartItemsResponse.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    // MARK: - Checkout

    /// `POST /order/checkout`. With `paymentMethod = .bunqMe` (default) this
    /// mints a bunq.me URL and the backend's poller will fire the SSE
    /// `order_status: paid` event when the user pays in bunq. With
    /// `paymentMethod = .mealCard` the backend debits the user's monthly
    /// meal-card sub-account synchronously and returns `status: "paid"` with
    /// `paymentURL: nil` — no SSE wait needed.
    ///
    /// In mock mode we still schedule a fake paid event for the bunq.me path.
    func checkout(
        cartId: String,
        paymentMethod: CheckoutPaymentMethod = .bunqMe
    ) async throws -> CheckoutResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            let orderId = "order-\(UUID().uuidString.prefix(8))"
            let isMealCard = paymentMethod == .mealCard
            let response = CheckoutResponse(
                orderId: String(orderId),
                paymentURL: isMealCard ? nil : MockData.checkoutResponse.paymentURL,
                amountEur: MockData.checkoutResponse.amountEur,
                paymentMethod: paymentMethod.rawValue,
                status: isMealCard ? "paid" : "ready_to_pay"
            )
            if !isMealCard {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    RealtimeService.shared.simulate(.orderStatus(OrderStatusEvent(
                        orderId: response.orderId ?? String(orderId),
                        status: "paid",
                        paidAt: Date()
                    )))
                }
            }
            return response
        }

        guard let url = URL(string: "\(baseURL)/order/checkout") else { throw APIError.invalidURL }
        var req = authedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "cart_id": cartId,
            "payment_method": paymentMethod.rawValue,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(CheckoutResponse.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    /// `GET /orders?status=paid&limit=...`. Returns the user's paid order
    /// history with the recipe name backfilled by the backend join.
    func getPaidOrders(limit: Int = 50) async throws -> [Order] {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            return []
        }
        guard let url = URL(string: "\(baseURL)/orders?status=paid&limit=\(limit)") else {
            throw APIError.invalidURL
        }
        let req = authedRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode([Order].self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    /// `POST /orders/{order_id}/mark-paid`. The bunq.me path uses production
    /// URLs that we can't poll for status; the user taps "I already paid"
    /// after the iDEAL flow and iOS calls this to flip the order to paid in
    /// the backend (so it ends up in order history + autologs the meal).
    @discardableResult
    func markOrderPaid(orderId: String) async throws -> Void {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            return
        }
        guard let url = URL(string: "\(baseURL)/orders/\(orderId)/mark-paid") else {
            throw APIError.invalidURL
        }
        let req = authedRequest(url: url, method: "POST")
        let (data, response) = try await URLSession.shared.data(for: req)
        _ = try await handle(data, response)
    }

    // MARK: - Meal card

    /// `GET /meal-card/current`. Returns nil on a 404 (no card for the current
    /// month yet) instead of throwing, so callers can render the setup CTA
    /// without exception handling.
    func getCurrentMealCard() async throws -> MealCard? {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            return nil
        }

        guard let url = URL(string: "\(baseURL)/meal-card/current") else {
            throw APIError.invalidURL
        }
        let req = authedRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            if http.statusCode == 401 {
                await AuthService.shared.handleUnauthorized()
                throw APIError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                throw APIError.server(http.statusCode)
            }
        }
        do { return try decoder.decode(MealCard.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    /// `POST /meal-card` — creates the current month's card with the given
    /// budget, or returns the existing card if one already exists for this
    /// month (idempotent).
    func createMealCard(budgetEur: Double) async throws -> MealCard {
        if useMockData {
            try await Task.sleep(nanoseconds: 700_000_000)
            return MockData.makeMealCard(budgetEur: budgetEur, balanceEur: budgetEur)
        }

        guard let url = URL(string: "\(baseURL)/meal-card") else { throw APIError.invalidURL }
        var req = authedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "monthly_budget_eur": budgetEur,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(MealCard.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    /// `POST /meal-card/topup` — adds funds to the current month's card.
    func topUpMealCard(amountEur: Double) async throws -> MealCard {
        if useMockData {
            try await Task.sleep(nanoseconds: 400_000_000)
            return MockData.makeMealCard(budgetEur: 300, balanceEur: 200 + amountEur)
        }

        guard let url = URL(string: "\(baseURL)/meal-card/topup") else { throw APIError.invalidURL }
        var req = authedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "amount_eur": amountEur,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(MealCard.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    /// `GET /meal-card/transactions?limit=...`.
    func getMealCardTransactions(limit: Int = 50) async throws -> [MealCardTransaction] {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            return []
        }

        guard let url = URL(string: "\(baseURL)/meal-card/transactions?limit=\(limit)") else {
            throw APIError.invalidURL
        }
        let req = authedRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode([MealCardTransaction].self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    // MARK: - Share-cost (post-checkout bunq.me split link)

    /// `POST /orders/{order_id}/share-cost`. Idempotent on the backend for
    /// matching (order, participant_count, include_self).
    func createShareCost(
        orderId: String,
        participantCount: Int,
        includeSelf: Bool = true
    ) async throws -> MealShare {
        if useMockData {
            try await Task.sleep(nanoseconds: 600_000_000)
            return MockData.makeShareCost(
                orderId: orderId,
                participantCount: participantCount,
                includeSelf: includeSelf
            )
        }

        guard let url = URL(string: "\(baseURL)/orders/\(orderId)/share-cost") else {
            throw APIError.invalidURL
        }
        var req = authedRequest(url: url, method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "participant_count": participantCount,
            "include_self": includeSelf,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        let validData = try await handle(data, response)
        do { return try decoder.decode(MealShare.self, from: validData) }
        catch { throw APIError.decoding(error) }
    }

    /// `GET /orders/{order_id}/share-cost`. Returns nil on 404 (no share has
    /// been generated for this order yet).
    func getShareCost(orderId: String) async throws -> MealShare? {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            return nil
        }

        guard let url = URL(string: "\(baseURL)/orders/\(orderId)/share-cost") else {
            throw APIError.invalidURL
        }
        let req = authedRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            if http.statusCode == 401 {
                await AuthService.shared.handleUnauthorized()
                throw APIError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                throw APIError.server(http.statusCode)
            }
        }
        do { return try decoder.decode(MealShare.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
