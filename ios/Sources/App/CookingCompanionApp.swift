import SwiftUI

@main
struct CookingCompanionApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var health = HealthKitService.shared
    @StateObject private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(health)
                .environmentObject(auth)
                .preferredColorScheme(.light)
                .task {
                    health.bind(appState)
                    if health.isAuthorized {
                        await health.refresh()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Group {
            if auth.isAuthenticated {
                ContentView()
            } else {
                AuthLandingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: auth.isAuthenticated)
    }
}
