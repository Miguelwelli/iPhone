import Foundation
import SwiftUI

/// Observable façade over `CatalogRepository` for SwiftUI.
///
/// The repository stays the single source of truth (and remains unit-tested on Linux); this type only
/// publishes snapshots to the views and centralizes error reporting.
@MainActor
public final class CatalogStore: ObservableObject {

    @Published public private(set) var games: [Game] = []
    @Published public private(set) var favorites: Set<UUID> = []
    @Published public private(set) var recentlyViewed: [Game] = []
    @Published public var lastError: String?

    /// Exposed so the assistant can reuse the same persistence layer (never a second catalog).
    public let repository: CatalogRepository

    public init(repository: CatalogRepository) {
        self.repository = repository
        reload()
    }

    public func reload() {
        games = repository.games
        favorites = repository.favorites
        recentlyViewed = repository.recentlyViewedGames
    }

    // MARK: - Derived collections

    public var featured: Game? { CatalogQuery.featured(in: games) }
    public var popular: [Game] { CatalogQuery.popular(in: games) }
    public var recentlyAdded: [Game] { CatalogQuery.recentlyAdded(in: games) }
    public var favoriteGames: [Game] { games.filter { favorites.contains($0.id) } }

    public func filtered(_ filter: CatalogFilter) -> [Game] {
        CatalogQuery.apply(games, filter: filter)
    }

    public func game(id: UUID) -> Game? { games.first { $0.id == id } }

    public func count(for category: String) -> Int {
        games.lazy.filter { $0.categories.contains(category) }.count
    }

    public var categoriesInUse: [GameCategory] {
        let used = Set(games.flatMap(\.categories))
        return GameCategory.all.filter { used.contains($0.rawValue) }
    }

    // MARK: - Mutations

    @discardableResult
    public func add(_ draft: GameDraft) -> Result<Game, CatalogError> {
        let game = draft.makeGame()
        do {
            try repository.add(game)
            reload()
            return .success(game)
        } catch let error as CatalogError {
            lastError = error.errorDescription
            return .failure(error)
        } catch {
            lastError = error.localizedDescription
            return .failure(.persistence(error.localizedDescription))
        }
    }

    @discardableResult
    public func update(_ draft: GameDraft, existing: Game) -> Result<Game, CatalogError> {
        let game = draft.makeGame(existing: existing)
        do {
            try repository.update(game)
            reload()
            return .success(game)
        } catch let error as CatalogError {
            lastError = error.errorDescription
            return .failure(error)
        } catch {
            lastError = error.localizedDescription
            return .failure(.persistence(error.localizedDescription))
        }
    }

    @discardableResult
    public func delete(_ game: Game) -> Bool {
        do {
            try repository.delete(id: game.id)
            reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func toggleFavorite(_ game: Game) {
        do {
            try repository.setFavorite(game.id, isFavorite: !favorites.contains(game.id))
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func isFavorite(_ game: Game) -> Bool { favorites.contains(game.id) }

    public func recordView(_ game: Game) {
        try? repository.recordView(game.id)
        reload()
    }
}
