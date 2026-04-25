import Foundation
import SwiftUI

enum MessageRole { case user, assistant }

struct ChatMessage: Identifiable {
    let id        = UUID()
    let role:     MessageRole
    let text:     String
    let recipes:  [Recipe]?
    let timestamp = Date()

    init(role: MessageRole, text: String, recipes: [Recipe]? = nil) {
        self.role    = role
        self.text    = text
        self.recipes = recipes
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages:         [ChatMessage] = []
    @Published var streamingText:    String        = ""
    @Published var suggestedRecipes: [Recipe]      = []
    @Published var isLoading:        Bool          = false

    private let api = APIService.shared
    private var activeTask: Task<Void, Never>?

    func send(_ text: String, profile: UserProfile) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        activeTask?.cancel()
        messages.append(.init(role: .user, text: trimmed))
        isLoading     = true
        streamingText = ""

        activeTask = Task { [weak self] in
            await self?.run(prompt: trimmed, profile: profile)
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask    = nil
        streamingText = ""
        isLoading     = false
    }

    func reset() {
        cancel()
        messages         = []
        suggestedRecipes = []
    }

    private func run(prompt: String, profile: UserProfile) async {
        var fullResponse = ""
        do {
            for try await chunk in api.streamChat(prompt: prompt, profile: profile) {
                try Task.checkCancellation()
                fullResponse  += chunk
                streamingText  = fullResponse
            }
        } catch is CancellationError {
            streamingText = ""
            isLoading     = false
            return
        } catch {
            fullResponse = "Sorry, something went wrong. Please try again."
        }
        streamingText = ""

        if Task.isCancelled {
            isLoading = false
            return
        }

        do {
            let recipes = try await api.fetchRecipes(prompt: prompt, profile: profile)
            try Task.checkCancellation()
            suggestedRecipes = recipes
            messages.append(.init(role: .assistant, text: fullResponse, recipes: recipes))
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            messages.append(.init(role: .assistant, text: fullResponse))
        }
        isLoading  = false
        activeTask = nil
    }
}
