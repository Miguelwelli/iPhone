import SwiftUI

@main
struct NexusStoreApp: App {

    @StateObject private var catalog: CatalogStore
    @StateObject private var transfers: TransferCoordinator
    @StateObject private var discovery: PS4ConnectionService
    @StateObject private var router = AppRouter()
    @StateObject private var session = AdminSession()
    @StateObject private var settings: SettingsStore
    @StateObject private var autoCatalog: AutoCatalogStore

    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment()
        self.environment = environment
        _catalog = StateObject(wrappedValue: CatalogStore(repository: environment.catalog))
        _transfers = StateObject(wrappedValue: environment.transfers)
        _discovery = StateObject(wrappedValue: environment.discovery)
        _settings = StateObject(wrappedValue: environment.settings)
        _autoCatalog = StateObject(wrappedValue: environment.autoCatalog)
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                catalog: catalog,
                transfers: transfers,
                discovery: discovery,
                preferences: environment.preferences,
                router: router,
                settings: settings
            )
            .environmentObject(session)
            .environmentObject(settings)
            .environmentObject(autoCatalog)
            .preferredColorScheme(.dark)
            .tint(NexusTheme.Palette.redBright)
        }
    }
}

/// Hash-based navigation destinations (keeps deep links within one tab simple and testable).
@MainActor
public final class AppRouter: ObservableObject {
    @Published public var section: AppSection = .home
    @Published public var homePath = NavigationPath()
    @Published public var gamesPath = NavigationPath()
    @Published public var categoriesPath = NavigationPath()
    @Published public var searchPath = NavigationPath()
    @Published public var ps4Path = NavigationPath()
    @Published public var showTransferSettings = false

    public func open(_ game: Game, from section: AppSection? = nil) {
        let target = section ?? self.section
        switch target {
        case .home: homePath.append(game)
        case .games: gamesPath.append(game)
        case .categories: categoriesPath.append(game)
        case .search: searchPath.append(game)
        case .ps4: ps4Path.append(game)
        }
    }

    public func show(_ destination: PS4Destination) {
        section = .ps4
        ps4Path.append(destination)
    }
}

public enum PS4Destination: Hashable {
    case transfers
    case manualSetup
}

/// Admin authentication state for the current app session.
@MainActor
public final class AdminSession: ObservableObject {
    @Published public var isUnlocked = false
}
