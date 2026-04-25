import SwiftUI

@main
struct CookingCompanionApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var health = HealthKitService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(health)
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
