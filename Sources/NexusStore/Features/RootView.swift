import SwiftUI

/// App shell: background, the five sections and the floating tab bar.
struct RootView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var transfers: TransferCoordinator
    @ObservedObject var discovery: PS4ConnectionService
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: SettingsStore
    let preferences: PreferencesStore

    var body: some View {
        ZStack(alignment: .bottom) {
            NexusBackground()

            Group {
                switch router.section {
                case .home:
                    NavigationStack(path: $router.homePath) {
                        HomeView(catalog: catalog, transfers: transfers, router: router, settings: settings)
                            .navigationDestination(for: Game.self) { game in
                                GameDetailView(gameID: game.id, catalog: catalog, transfers: transfers, discovery: discovery, router: router)
                            }
                    }
                case .games:
                    NavigationStack(path: $router.gamesPath) {
                        CatalogView(catalog: catalog, router: router, initialCategory: nil, title: "Catálogo", subtitle: "Explorar jogos para PS4")
                            .navigationDestination(for: Game.self) { game in
                                GameDetailView(gameID: game.id, catalog: catalog, transfers: transfers, discovery: discovery, router: router)
                            }
                    }
                case .categories:
                    NavigationStack(path: $router.categoriesPath) {
                        CategoriesView(catalog: catalog, router: router)
                            .navigationDestination(for: Game.self) { game in
                                GameDetailView(gameID: game.id, catalog: catalog, transfers: transfers, discovery: discovery, router: router)
                            }
                    }
                case .search:
                    NavigationStack(path: $router.searchPath) {
                        SearchView(catalog: catalog, router: router, preferences: preferences, transfers: transfers)
                            .navigationDestination(for: Game.self) { game in
                                GameDetailView(gameID: game.id, catalog: catalog, transfers: transfers, discovery: discovery, router: router)
                            }
                    }
                case .ps4:
                    NavigationStack(path: $router.ps4Path) {
                        PS4View(discovery: discovery, transfers: transfers, router: router)
                            .navigationDestination(for: Game.self) { game in
                                GameDetailView(gameID: game.id, catalog: catalog, transfers: transfers, discovery: discovery, router: router)
                            }
                            .navigationDestination(for: PS4Destination.self) { destination in
                                switch destination {
                                case .transfers:
                                    TransferCenterView(transfers: transfers)
                                case .manualSetup:
                                    ManualConsoleView(discovery: discovery)
                                }
                            }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: NexusTheme.Metrics.tabBarHeight)
            }

            NexusTabBar(
                selection: $router.section,
                transferBadge: transfers.hasActiveTransfer,
                transferProgress: transfers.activeJob.map { $0.progress }
            )
        }
        .animation(.easeInOut(duration: 0.2), value: router.section)
    }
}
