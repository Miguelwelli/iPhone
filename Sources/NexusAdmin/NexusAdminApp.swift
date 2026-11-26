import SwiftUI

@main
struct NexusAdminApp: App {
    @StateObject private var service = SupabaseService()
    @State private var selectedTab: Int = 0
    @State private var showSettings: Bool = false

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                DashboardView(
                    service: service,
                    onNavigateToCreate: { selectedTab = 1 },
                    onNavigateToCatalog: { selectedTab = 2 },
                    onOpenSettings: { showSettings = true }
                )
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                .tag(0)

                GameFormView(service: service, editingGame: nil) {
                    selectedTab = 2
                }
                .tabItem {
                    Label("Cadastrar", systemImage: "plus.circle.fill")
                }
                .tag(1)

                CatalogView(service: service)
                    .tabItem {
                        Label("Catálogo", systemImage: "books.vertical.fill")
                    }
                    .tag(2)
            }
            .tint(NexusTheme.electricGlow)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showSettings) {
                SettingsView(service: service)
            }
            .task {
                if service.config.isConfigured {
                    _ = await service.testConnection()
                    await service.fetchGames()
                }
            }
        }
    }
}
