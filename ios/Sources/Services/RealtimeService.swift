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

/// `image_url` arrives as a data: URL (~2 MB base64). Decoding that into Swift's
/// `URL` is fragile for very long strings, so we keep it as a String here and
/// let consumers convert lazily (or render the base64 directly).
struct ImageReadyEvent: Codable, Hashable {
    let recipeId: String
    let imageURL: String

    var resolvedURL: URL? { URL(string: imageURL) }

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
    let ts: String
}

// MARK: - Event sum type

enum RealtimeEvent: Hashable {
    case ping(String)
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
        case retrying(after: Int)
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var lastEvent: RealtimeEvent?

    private var task: Task<Void, Never>?
    private var activeReader: SSEStreamReader?
    private var continuations: [UUID: AsyncStream<RealtimeEvent>.Continuation] = [:]

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    // MARK: - Subscription fan-out

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

    func start() {
        guard task == nil else { return }
        connectionState = .connecting
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// Synchronously tears down the in-flight URLSession so a follow-up `start()`
    /// can't double-connect. The owning Task observes cancellation on its next
    /// suspension point and exits the run loop.
    func stop() {
        activeReader?.shutdown()
        activeReader = nil
        task?.cancel()
        task = nil
        connectionState = .disconnected
    }

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
                backoffSeconds = 1
            } catch is CancellationError {
                return
            } catch {
                print("[Realtime] connect/stream error: \(error)")
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
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if Task.isCancelled { return }
            publish(.ping(ISO8601DateFormatter().string(from: Date())))
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
        // Disable the system Accept-Encoding so the response can't come back
        // gzipped — gzipped chunked SSE is a well-known source of buffering.
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let reader = SSEStreamReader(request: req)
        activeReader = reader
        defer {
            if activeReader === reader { activeReader = nil }
            reader.shutdown()
        }

        for try await message in reader.events() {
            try Task.checkCancellation()

            // First message implies headers were accepted.
            if connectionState != .connected {
                connectionState = .connected
            }

            let event = decode(name: message.name, data: message.data)
            publish(event)
        }
    }

    // MARK: - Decoding

    private func decode(name: String, data: String) -> RealtimeEvent {
        guard let payload = data.data(using: .utf8) else {
            print("[Realtime] event '\(name)' had non-UTF8 data; dropping")
            return .unknown(name: name, raw: data)
        }

        do {
            switch name {
            case "ping":
                let evt = try decoder.decode(PingEvent.self, from: payload)
                return .ping(evt.ts)
            case "recipe_complete":
                let evt = try decoder.decode(RecipeCompleteEvent.self, from: payload)
                return .recipeComplete(evt)
            case "image_ready":
                let evt = try decoder.decode(ImageReadyEvent.self, from: payload)
                return .imageReady(evt)
            case "cart_ready":
                let evt = try decoder.decode(CartReadyEvent.self, from: payload)
                return .cartReady(evt)
            case "order_status":
                let evt = try decoder.decode(OrderStatusEvent.self, from: payload)
                return .orderStatus(evt)
            case "error":
                let evt = try decoder.decode(RealtimeErrorEvent.self, from: payload)
                return .error(evt)
            default:
                return .unknown(name: name, raw: data)
            }
        } catch {
            // Surfacing this is critical: previously every decode error became a
            // silent .unknown and the chat appeared to hang.
            let preview = data.count > 240 ? String(data.prefix(240)) + "…" : data
            print("[Realtime] decode failed for event '\(name)': \(error) — payload: \(preview)")
            return .unknown(name: name, raw: data)
        }
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

// MARK: - SSE byte streamer

/// Streams Server-Sent Events via `URLSessionDataDelegate` instead of
/// `URLSession.bytes(for:)`. The delegate-based path receives bytes the moment
/// the OS sees them and bypasses the AsyncBytes/AsyncLineSequence pipeline,
/// which has been observed to buffer chunked-encoded streams on iOS.
private final class SSEStreamReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Message {
        let name: String
        let data: String
    }

    private let request: URLRequest

    // All mutable state below is touched only on the URLSession delegate queue
    // (a serial queue we own), or under `continuationLock` from any thread.
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var byteBuffer = Data()
    private var currentEvent: String?
    private var dataLines: [String] = []

    private let continuationLock = NSLock()
    private var continuation: AsyncThrowingStream<Message, Error>.Continuation?

    private let delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "SSEStreamReader.delegate"
        return q
    }()

    init(request: URLRequest) {
        self.request = request
        super.init()
    }

    deinit { shutdown() }

    func events() -> AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream { cont in
            self.continuationLock.lock()
            self.continuation = cont
            self.continuationLock.unlock()

            cont.onTermination = { [weak self] _ in
                self?.shutdown()
            }

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 600       // 10 min between bytes
            config.timeoutIntervalForResource = 86_400   // 24 h total
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.httpShouldUsePipelining = false

            let session = URLSession(
                configuration: config,
                delegate: self,
                delegateQueue: self.delegateQueue
            )
            self.session = session

            let dataTask = session.dataTask(with: self.request)
            self.task = dataTask
            dataTask.resume()
        }
    }

    /// Idempotent. Cancels the URLSession task and finishes the stream so the
    /// consumer's `for try await` exits.
    func shutdown() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil

        continuationLock.lock()
        continuation?.finish()
        continuation = nil
        continuationLock.unlock()
    }

    private func finish(throwing error: Error) {
        continuationLock.lock()
        continuation?.finish(throwing: error)
        continuation = nil
        continuationLock.unlock()
    }

    private func yield(_ message: Message) {
        continuationLock.lock()
        continuation?.yield(message)
        continuationLock.unlock()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }
        switch http.statusCode {
        case 200...299:
            completionHandler(.allow)
        case 401:
            finish(throwing: RealtimeError.unauthorized)
            completionHandler(.cancel)
        default:
            finish(throwing: RealtimeError.serverStatus(http.statusCode))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        byteBuffer.append(data)
        emitCompletedLines()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let nsError = error as NSError?, nsError.code == NSURLErrorCancelled {
            // Cancellation is expected on stop(); finish cleanly.
            continuationLock.lock()
            continuation?.finish()
            continuation = nil
            continuationLock.unlock()
        } else if let error {
            finish(throwing: error)
        } else {
            continuationLock.lock()
            continuation?.finish()
            continuation = nil
            continuationLock.unlock()
        }
    }

    // MARK: SSE parsing

    private func emitCompletedLines() {
        while let lineEnd = byteBuffer.firstIndex(of: 0x0A) {
            var lineSlice = byteBuffer[byteBuffer.startIndex..<lineEnd]
            if lineSlice.last == 0x0D { lineSlice = lineSlice.dropLast() }
            let line = String(decoding: lineSlice, as: UTF8.self)
            byteBuffer.removeSubrange(byteBuffer.startIndex...lineEnd)
            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        if line.isEmpty {
            if let name = currentEvent, !dataLines.isEmpty {
                let payload = dataLines.joined(separator: "\n")
                yield(Message(name: name, data: payload))
            }
            currentEvent = nil
            dataLines.removeAll(keepingCapacity: true)
            return
        }
        if line.hasPrefix(":") { return }
        if let value = stripPrefix(line, "event:") {
            currentEvent = value
        } else if let value = stripPrefix(line, "data:") {
            dataLines.append(value)
        }
    }

    private func stripPrefix(_ line: String, _ prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let raw = line.dropFirst(prefix.count)
        if raw.hasPrefix(" ") { return String(raw.dropFirst()) }
        return String(raw)
    }
}
