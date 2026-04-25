import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case network(Error)
    case server(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid URL"
        case .network(let e):   return e.localizedDescription
        case .server(let code): return "Server error \(code)"
        case .decoding(let e):  return "Decode error: \(e.localizedDescription)"
        }
    }
}

// Toggle useMockData → false once backend is reachable.
// Update baseURL to the Fly.io/Railway deployment URL.
class APIService {
    static let shared = APIService()
    private init() {}

    var baseURL = "http://localhost:8000"
    var useMockData = true

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

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

    // MARK: - Cart
    func buildCart(from recipe: Recipe, people: Int, store: String? = nil) async throws -> CartResponse {
        if useMockData {
            try await Task.sleep(nanoseconds: 600_000_000)
            return MockData.cart(for: store)
        }

        guard let url = URL(string: "\(baseURL)/cart/from-recipe") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "recipe_id": recipe.id,
            "people": people,
        ]
        if let store { body["store"] = store }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        do { return try decoder.decode(CartResponse.self, from: data) }
        catch { throw APIError.decoding(error) }
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
        req.httpBody = try? JSONEncoder().encode(cart)

        let (data, _) = try await URLSession.shared.data(for: req)
        do { return try decoder.decode(CheckoutResponse.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
