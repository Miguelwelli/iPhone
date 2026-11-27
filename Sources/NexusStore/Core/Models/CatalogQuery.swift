import Foundation

/// Sorting options offered in the catalog screen.
public enum CatalogSort: String, CaseIterable, Identifiable, Sendable {
    case popular
    case recent
    case name
    case size

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .popular: return "Mais Jogados"
        case .recent: return "Mais Recentes"
        case .name: return "Nome (A-Z)"
        case .size: return "Maior Tamanho"
        }
    }
}

/// Pure, testable filtering + sorting applied to the catalog.
public struct CatalogFilter: Equatable, Sendable {
    public var searchText: String = ""
    /// Empty means "todos".
    public var categories: Set<String> = []
    public var sort: CatalogSort = .popular

    public init(searchText: String = "", categories: Set<String> = [], sort: CatalogSort = .popular) {
        self.searchText = searchText
        self.categories = categories
        self.sort = sort
    }

    public var isEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && categories.isEmpty
    }
}

public enum CatalogQuery {

    /// Applies search + category filters, then sorts.
    public static func apply(_ games: [Game], filter: CatalogFilter) -> [Game] {
        let needle = SearchText.fold(filter.searchText)
        var result = games.filter { game in
            let matchesSearch = needle.isEmpty || game.searchableText.contains(needle)
            let matchesCategory = filter.categories.isEmpty || !Set(game.categories).isDisjoint(with: filter.categories)
            return matchesSearch && matchesCategory
        }
        result.sort { lhs, rhs in
            switch filter.sort {
            case .popular:
                if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
                if lhs.ratingCount != rhs.ratingCount { return lhs.ratingCount > rhs.ratingCount }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .recent:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size:
                if lhs.byteCount != rhs.byteCount { return lhs.byteCount > rhs.byteCount }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        return result
    }

    /// The single game shown in the hero banner: explicit `isFeatured` wins, then best rated.
    public static func featured(in games: [Game]) -> Game? {
        games.filter(\.isFeatured).max(by: { $0.updatedAt < $1.updatedAt })
            ?? games.filter { $0.rating > 0 }.max(by: { $0.rating < $1.rating })
            ?? games.first
    }

    /// Games added most recently (independent from the search filter, used by the home screen).
    public static func recentlyAdded(in games: [Game], limit: Int = 6) -> [Game] {
        Array(games.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    /// "Populares" row: highest rated first.
    public static func popular(in games: [Game], limit: Int = 10) -> [Game] {
        Array(games.sorted {
            if $0.rating != $1.rating { return $0.rating > $1.rating }
            return $0.ratingCount > $1.ratingCount
        }.prefix(limit))
    }

    /// Count of games per category raw value.
    public static func categoryCounts(in games: [Game]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for game in games {
            for category in game.categories {
                counts[category, default: 0] += 1
            }
        }
        return counts
    }
}
