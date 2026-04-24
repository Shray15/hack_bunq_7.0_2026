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
    var profile     = UserProfile()

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        messages.append(.init(role: .user, text: trimmed))
        isLoading     = true
        streamingText = ""

        // Stream the assistant text
        var fullResponse = ""
        do {
            for try await chunk in api.streamChat(prompt: trimmed, profile: profile) {
                fullResponse  += chunk
                streamingText  = fullResponse
            }
        } catch {
            fullResponse = "Sorry, something went wrong. Please try again."
        }
        streamingText = ""

        // Fetch recipe cards
        do {
            let recipes = try await api.fetchRecipes(prompt: trimmed, profile: profile)
            suggestedRecipes = recipes
            messages.append(.init(role: .assistant, text: fullResponse, recipes: recipes))
        } catch {
            messages.append(.init(role: .assistant, text: fullResponse))
        }
        isLoading = false
    }

    func reset() {
        messages         = []
        suggestedRecipes = []
        streamingText    = ""
    }
}
