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

    var baseURL = "http://localhost:4567"
    var useMockData = true

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
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

    // MARK: - Chat SSE stream
    /// Streams assistant text tokens. Each yielded value is a raw text chunk.
    func streamChat(prompt: String, profile: UserProfile) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if useMockData {
                    let chunks = ["Let me find something perfect for you…", " Here are 3 options that hit your goals."]
                    for chunk in chunks {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                    return
                }

                guard let url = URL(string: "\(baseURL)/chat") else {
                    continuation.finish(throwing: APIError.invalidURL)
                    return
                }

                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json",    forHTTPHeaderField: "Content-Type")
                req.setValue("text/event-stream",   forHTTPHeaderField: "Accept")
                req.httpBody = try? JSONSerialization.data(withJSONObject: [
                    "prompt": prompt,
                    "diet": profile.dietType.rawValue,
                    "calories": profile.dailyCalorieTarget,
                ])

                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: req)
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.network(error))
                }
            }
        }
    }

    // MARK: - Recipes
    func fetchRecipes(prompt: String, profile: UserProfile) async throws -> [Recipe] {
        if useMockData {
            try await Task.sleep(nanoseconds: 1_200_000_000)
            return MockData.recipes
        }

        guard let url = URL(string: "\(baseURL)/recipes/generate") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "prompt": prompt,
            "diet": profile.dietType.rawValue,
        ])

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.server((res as? HTTPURLResponse)?.statusCode ?? 0)
        }
        do { return try decoder.decode([Recipe].self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    // MARK: - Cart (new 2-step flow)

    /// `POST /cart/from-recipe` — returns store totals only, no items yet.
    func compareStores(recipeId: String, people: Int) async throws -> CartComparisonResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            return MockData.comparisonResponse
        }

        guard let url = URL(string: "\(baseURL)/cart/from-recipe") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "recipe_id": recipeId,
            "people": people,
        ])

        let (data, _) = try await URLSession.shared.data(for: req)
        do { return try decoder.decode(CartComparisonResponse.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    /// `POST /cart/{cart_id}/select-store` — returns the item list with images.
    func selectStore(cartId: String, store: String) async throws -> CartItemsResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 400_000_000)
            return MockData.itemsResponse(for: store)
        }

        guard let url = URL(string: "\(baseURL)/cart/\(cartId)/select-store") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["store": store])

        let (data, _) = try await URLSession.shared.data(for: req)
        do { return try decoder.decode(CartItemsResponse.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    // MARK: - Cart (transitional single-call shim, used by current OrderCheckoutView)

    /// Builds a merged `CartResponse` (comparison + items) so the existing view
    /// keeps working until phase 4 splits it across the two new endpoints.
    func buildCart(from recipe: Recipe, people: Int, store: String? = nil) async throws -> CartResponse {
        let comparison = try await compareStores(recipeId: recipe.id, people: people)
        let chosenStore = store ?? comparison.comparison.min(by: { $0.totalEur < $1.totalEur })?.store ?? "ah"
        let items = try await selectStore(cartId: comparison.cartId, store: chosenStore)
        return CartResponse.merge(comparison: comparison, items: items)
    }

    // MARK: - Checkout
    func checkout(cart: CartResponse) async throws -> CheckoutResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            return MockData.checkoutResponse
        }

        guard let url = URL(string: "\(baseURL)/order/checkout") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["cart_id": cart.id])

        let (data, _) = try await URLSession.shared.data(for: req)
        do { return try decoder.decode(CheckoutResponse.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
