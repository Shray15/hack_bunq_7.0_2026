import SwiftUI

struct ContentView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView(selectedTab: $tab)
                .tabItem { Label("Today",   systemImage: "house.fill") }
                .tag(0)

            ChatView()
                .tabItem { Label("Plan",    systemImage: "sparkles") }
                .tag(1)

            NutritionTrackerView()
                .tabItem { Label("Track",   systemImage: "chart.bar.fill") }
                .tag(2)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(3)
        }
        .tint(AppTheme.primary)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(AppTheme.card, for: .tabBar)
    }
}
