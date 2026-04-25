import SwiftUI

@main
struct CookingCompanionApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var health = HealthKitService.shared
    @StateObject private var auth = AuthService.shared
    @StateObject private var realtime = RealtimeService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(health)
                .environmentObject(auth)
                .environmentObject(realtime)
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
    @EnvironmentObject private var realtime: RealtimeService
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

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
        .onAppear {
            syncRealtime()
            if auth.isAuthenticated {
                appState.reloadForCurrentUser()
                Task { await appState.refreshProfileFromBackend() }
            }
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthed in
            syncRealtime()
            if isAuthed {
                // New session — pull this user's persisted recipes / planned
                // meals / chat history off disk before first paint.
                appState.reloadForCurrentUser()
                Task { await appState.refreshProfileFromBackend() }
            }
        }
        .onChange(of: scenePhase) { _, _ in syncRealtime() }
    }

    /// Realtime is on only while the user is authenticated AND the scene is active.
    /// start/stop are idempotent so calling this from multiple triggers is safe.
    private func syncRealtime() {
        if auth.isAuthenticated && scenePhase == .active {
            realtime.start()
        } else {
            realtime.stop()
        }
    }
}
