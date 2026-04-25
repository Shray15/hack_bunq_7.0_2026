import Foundation
import Combine

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    /// Account name used for every stored auth secret.
    nonisolated static let keychainAccount = "cooking-companion"

    @Published private(set) var token: String?
    @Published private(set) var isWorking: Bool = false
    @Published var lastError: String?

    var isAuthenticated: Bool { token != nil }

    private let api = APIService.shared

    private init() {
        token = KeychainStore.read(Self.keychainAccount)
    }

    /// `POST /auth/signup`. On success persists the JWT and flips `isAuthenticated`.
    func signup(email: String, password: String) async {
        await runAuthCall {
            try await api.signup(email: email, password: password)
        }
    }

    /// `POST /auth/login`. On success persists the JWT and flips `isAuthenticated`.
    func login(email: String, password: String) async {
        await runAuthCall {
            try await api.login(email: email, password: password)
        }
    }

    /// User-initiated sign-out. Clears in-memory + keychain state.
    func logout() {
        token = nil
        KeychainStore.delete(Self.keychainAccount)
    }

    /// Called by APIService when an authed call returns 401.
    /// Wipes state so the root view routes back to the auth screen.
    func handleUnauthorized() {
        guard token != nil else { return }
        logout()
        lastError = "Session expired. Please sign in again."
    }

    // MARK: - Helpers

    private func runAuthCall(_ work: @MainActor () async throws -> AuthResponse) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let response = try await work()
            token = response.accessToken
            KeychainStore.save(response.accessToken, for: Self.keychainAccount)
        } catch let APIError.server(code) where code == 401 {
            lastError = "Invalid email or password."
        } catch let APIError.server(code) where code == 409 {
            lastError = "An account with that email already exists."
        } catch let APIError.server(code) where code == 422 {
            lastError = "Email or password is not in a valid format."
        } catch APIError.unauthorized {
            lastError = "Invalid email or password."
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Wire shape of `/auth/signup` and `/auth/login` responses.
struct AuthResponse: Codable {
    let accessToken: String
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType   = "token_type"
    }
}
