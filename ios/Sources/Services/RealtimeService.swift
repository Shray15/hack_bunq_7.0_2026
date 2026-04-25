import Foundation
import Combine

// MARK: - Wire payloads

struct RecipeCompleteEvent: Codable, Hashable {
    let chatId: String
    let recipeId: String
    let recipe: Recipe

    enum CodingKeys: String, CodingKey {
        case chatId   = "chat_id"
        case recipeId = "recipe_id"
        case recipe
    }
}

struct ImageReadyEvent: Codable, Hashable {
    let recipeId: String
    let imageURL: URL

    enum CodingKeys: String, CodingKey {
        case recipeId = "recipe_id"
        case imageURL = "image_url"
    }
}

struct CartReadyEvent: Codable, Hashable {
    let cartId: String
    let comparison: [StoreComparison]

    enum CodingKeys: String, CodingKey {
        case cartId = "cart_id"
        case comparison
    }
}

struct OrderStatusEvent: Codable, Hashable {
    let orderId: String
    let status: String
    let paidAt: Date?

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case status
        case paidAt  = "paid_at"
    }
}

struct RealtimeErrorEvent: Codable, Hashable {
    let scope: String
    let code: String
    let message: String
}

struct PingEvent: Codable, Hashable {
    let ts: Date
}

// MARK: - Event sum type

enum RealtimeEvent: Hashable {
    case ping(Date)
    case recipeComplete(RecipeCompleteEvent)
    case imageReady(ImageReadyEvent)
    case cartReady(CartReadyEvent)
    case orderStatus(OrderStatusEvent)
    case error(RealtimeErrorEvent)
    case unknown(name: String, raw: String)
}

// MARK: - Service

@MainActor
final class RealtimeService: ObservableObject {
    static let shared = RealtimeService()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case retrying(after: Int)   // seconds
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var lastEvent: RealtimeEvent?

    private var task: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<RealtimeEvent>.Continuation] = [:]

    /// Long-lived session with generous timeouts so the SSE stream isn't killed.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 600     // 10 min
        config.timeoutIntervalForResource = 86_400  // 24 h
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    // MARK: - Subscription fan-out

    /// Each subscriber gets its own AsyncStream; events are broadcast to all.
    func subscribe() -> AsyncStream<RealtimeEvent> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    // MARK: - Lifecycle

    /// Idempotent. Opens the SSE channel if not already running.
    func start() {
        guard task == nil else { return }
        connectionState = .connecting
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// Idempotent. Tears the channel down. Call on logout, background, etc.
    func stop() {
        task?.cancel()
        task = nil
        connectionState = .disconnected
    }

    /// For mocks/tests: inject a synthetic event into all subscribers.
    func simulate(_ event: RealtimeEvent) {
        publish(event)
    }

    // MARK: - Run loop

    private func runLoop() async {
        if APIService.shared.useMockData {
            await mockLoop()
            return
        }

        var backoffSeconds: Int = 1
        let maxBackoff = 30

        while !Task.isCancelled {
            do {
                try await connectAndStream()
                // Stream ended cleanly — backend probably closed it. Reconnect.
                backoffSeconds = 1
            } catch is CancellationError {
                return
            } catch {
                // Connection failed or read error. Will back off below.
            }

            if Task.isCancelled { return }

            connectionState = .retrying(after: backoffSeconds)
            try? await Task.sleep(nanoseconds: UInt64(backoffSeconds) * 1_000_000_000)
            backoffSeconds = min(backoffSeconds * 2, maxBackoff)
        }
    }

    private func mockLoop() async {
        connectionState = .connected
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)   // 15 s
            if Task.isCancelled { return }
            publish(.ping(Date()))
        }
    }

    private func connectAndStream() async throws {
        guard let token = KeychainStore.read(AuthService.keychainAccount) else {
            throw RealtimeError.noToken
        }

        let base = APIService.shared.baseURL
        guard let url = URL(string: "\(base)/events/stream?token=\(token)") else {
            throw RealtimeError.invalidURL
        }

        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: req)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299:
                break
            case 401:
                AuthService.shared.handleUnauthorized()
                throw RealtimeError.unauthorized
            default:
                throw RealtimeError.serverStatus(http.statusCode)
            }
        }

        connectionState = .connected

        var currentEvent: String?
        var dataLines: [String] = []

        for try await line in bytes.lines {
            try Task.checkCancellation()

            if line.isEmpty {
                // SSE event boundary — dispatch and reset.
                if let name = currentEvent, !dataLines.isEmpty {
                    let payload = dataLines.joined(separator: "\n")
                    dispatch(eventName: name, data: payload)
                }
                currentEvent = nil
                dataLines.removeAll(keepingCapacity: true)
                continue
            }

            if line.hasPrefix(":") {
                continue   // SSE comment
            }

            if let value = parsedField(line, prefix: "event:") {
                currentEvent = value
            } else if let value = parsedField(line, prefix: "data:") {
                dataLines.append(value)
            }
            // id:, retry: etc. are not used by us; skip.
        }
    }

    private func parsedField(_ line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let raw = line.dropFirst(prefix.count)
        // Per spec a single leading space is stripped if present.
        if raw.hasPrefix(" ") {
            return String(raw.dropFirst())
        }
        return String(raw)
    }

    // MARK: - Decoding

    private func dispatch(eventName: String, data: String) {
        let event = decode(name: eventName, data: data)
        publish(event)
    }

    private func decode(name: String, data: String) -> RealtimeEvent {
        guard let payload = data.data(using: .utf8) else {
            return .unknown(name: name, raw: data)
        }

        switch name {
        case "ping":
            if let ping = try? decoder.decode(PingEvent.self, from: payload) {
                return .ping(ping.ts)
            }
        case "recipe_complete":
            if let evt = try? decoder.decode(RecipeCompleteEvent.self, from: payload) {
                return .recipeComplete(evt)
            }
        case "image_ready":
            if let evt = try? decoder.decode(ImageReadyEvent.self, from: payload) {
                return .imageReady(evt)
            }
        case "cart_ready":
            if let evt = try? decoder.decode(CartReadyEvent.self, from: payload) {
                return .cartReady(evt)
            }
        case "order_status":
            if let evt = try? decoder.decode(OrderStatusEvent.self, from: payload) {
                return .orderStatus(evt)
            }
        case "error":
            if let evt = try? decoder.decode(RealtimeErrorEvent.self, from: payload) {
                return .error(evt)
            }
        default:
            break
        }
        return .unknown(name: name, raw: data)
    }

    private func publish(_ event: RealtimeEvent) {
        lastEvent = event
        for (_, c) in continuations {
            c.yield(event)
        }
    }
}

enum RealtimeError: Error, LocalizedError {
    case noToken
    case invalidURL
    case unauthorized
    case serverStatus(Int)

    var errorDescription: String? {
        switch self {
        case .noToken:               return "Not signed in."
        case .invalidURL:            return "Bad realtime URL."
        case .unauthorized:          return "Session expired."
        case .serverStatus(let s):   return "Realtime server returned \(s)."
        }
    }
}
