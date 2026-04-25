import Foundation
import SwiftUI

enum MessageRole { case user, assistant }

struct ChatMessage: Identifiable {
    let id        = UUID()
    let role:     MessageRole
    var text:     String
    var recipes:  [Recipe]?
    let timestamp = Date()

    init(role: MessageRole, text: String, recipes: [Recipe]? = nil) {
        self.role    = role
        self.text    = text
        self.recipes = recipes
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    private let api = APIService.shared
    private let realtime = RealtimeService.shared
    private var pendingChatIds: Set<String> = []
    private var listenerTask: Task<Void, Never>?

    init() {
        let stream = realtime.subscribe()
        listenerTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    deinit {
        listenerTask?.cancel()
    }

    // MARK: - Public

    /// Sends the user's transcript to `POST /chat`. The recipe arrives later via SSE.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(.init(role: .user, text: trimmed))
        isLoading = true
        lastError = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.api.postChat(transcript: trimmed)
                self.pendingChatIds.insert(response.chatId)
            } catch is CancellationError {
                return
            } catch {
                self.appendAssistant(text: "Sorry, something went wrong. Please try again.")
                self.isLoading = false
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Drop everything we're waiting on so subsequent SSE events won't surprise the UI.
    func cancel() {
        pendingChatIds.removeAll()
        isLoading = false
    }

    func reset() {
        cancel()
        messages.removeAll()
        lastError = nil
    }

    // MARK: - Realtime handlers

    private func handle(_ event: RealtimeEvent) {
        switch event {
        case .recipeComplete(let payload):
            handleRecipeComplete(payload)
        case .imageReady(let payload):
            handleImageReady(payload)
        case .error(let payload) where payload.scope == "chat":
            handleChatError(payload)
        default:
            break
        }
    }

    private func handleRecipeComplete(_ payload: RecipeCompleteEvent) {
        guard pendingChatIds.contains(payload.chatId) else { return }
        pendingChatIds.remove(payload.chatId)

        appendAssistant(
            text: introText(for: payload.recipe),
            recipes: [payload.recipe]
        )

        if pendingChatIds.isEmpty {
            isLoading = false
        }
    }

    private func handleImageReady(_ payload: ImageReadyEvent) {
        // image_url is a (possibly multi-MB) data: URL on the wire. URL(string:)
        // can return nil for very long strings — if it does, leave the existing
        // (placeholder) imageURL in place rather than wiping it.
        guard let url = payload.resolvedURL else {
            print("[ChatVM] image_ready: URL(string:) returned nil for recipe \(payload.recipeId)")
            return
        }
        for messageIndex in messages.indices {
            guard var recipes = messages[messageIndex].recipes else { continue }
            guard let recipeIndex = recipes.firstIndex(where: { $0.id == payload.recipeId }) else { continue }
            recipes[recipeIndex] = recipes[recipeIndex].replacing(imageURL: url)
            messages[messageIndex].recipes = recipes
        }
    }

    private func handleChatError(_ payload: RealtimeErrorEvent) {
        appendAssistant(text: payload.message)
        pendingChatIds.removeAll()
        isLoading = false
        lastError = payload.message
    }

    // MARK: - Helpers

    private func appendAssistant(text: String, recipes: [Recipe]? = nil) {
        messages.append(.init(role: .assistant, text: text, recipes: recipes))
    }

    private func introText(for recipe: Recipe) -> String {
        let kcal = recipe.macros.calories
        let protein = recipe.macros.proteinG
        let mins = recipe.prepTimeMin
        return "Try \(recipe.name) — \(kcal) kcal · \(protein)g protein · \(mins) min."
    }
}
