import Foundation

/// Everything persisted on disk by the catalog.
public struct CatalogSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var games: [Game]
    public var favorites: [UUID]
    public var recentlyViewed: [UUID]
    /// True once the demo/seed catalog was installed. Kept so that deleting every game does not
    /// resurrect the seed catalog on the next launch.
    public var didSeed: Bool

    public init(
        schemaVersion: Int = CatalogSnapshot.currentSchemaVersion,
        games: [Game] = [],
        favorites: [UUID] = [],
        recentlyViewed: [UUID] = [],
        didSeed: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.games = games
        self.favorites = favorites
        self.recentlyViewed = recentlyViewed
        self.didSeed = didSeed
    }

    public static let currentSchemaVersion = 1

    /// Number of games showable in a category chip.
    public func count(for category: String) -> Int {
        games.lazy.filter { $0.categories.contains(category) }.count
    }
}

public enum CatalogError: LocalizedError, Equatable {
    case duplicateName(String)
    case notFound(UUID)
    case persistence(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateName(let name):
            return "Já existe um jogo chamado “\(name)” no catálogo."
        case .notFound:
            return "Jogo não encontrado."
        case .persistence(let message):
            return "Falha ao salvar o catálogo: \(message)"
        }
    }
}

/// File-backed catalog. The JSON file is written atomically on every mutation (catalogs are small —
/// a few hundred KB at most — so this is cheap and keeps the data safe if the app is killed).
///
/// Not thread-safe by design: the app calls it from the main actor, and tests use it synchronously.
public final class CatalogRepository {

    public private(set) var snapshot: CatalogSnapshot
    public let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates the repository and loads existing data.
    /// - Parameters:
    ///   - fileURL: destination JSON file (usually Application Support/Catalog/catalog.json).
    ///   - seed: games installed on first launch only (empty by default so tests are deterministic).
    public init(fileURL: URL, seed: [Game] = [], fileManager: FileManager = .default) throws {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = Self.makeEncoder()
        self.decoder = Self.makeDecoder()

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? decoder.decode(CatalogSnapshot.self, from: data) {
            snapshot = loaded
        } else {
            snapshot = CatalogSnapshot(games: seed, didSeed: !seed.isEmpty)
            if !seed.isEmpty {
                try persist()
            }
        }
    }

    // MARK: - Queries

    public var games: [Game] { snapshot.games }

    public var favorites: Set<UUID> { Set(snapshot.favorites) }

    public func game(id: UUID) -> Game? {
        snapshot.games.first { $0.id == id }
    }

    public func allCategoriesInUse() -> [GameCategory] {
        let used = Set(snapshot.games.flatMap(\.categories))
        return GameCategory.all.filter { used.contains($0.rawValue) }
    }

    /// Games ordered by the "recently viewed" list.
    public var recentlyViewedGames: [Game] {
        snapshot.recentlyViewed.compactMap(game(id:))
    }

    // MARK: - Mutations

    public func add(_ game: Game) throws {
        if snapshot.games.contains(where: { $0.name.caseInsensitiveCompare(game.name) == .orderedSame }) {
            throw CatalogError.duplicateName(game.name)
        }
        snapshot.games.append(game)
        try persist()
    }

    public func update(_ game: Game) throws {
        guard let index = snapshot.games.firstIndex(where: { $0.id == game.id }) else {
            throw CatalogError.notFound(game.id)
        }
        if snapshot.games.contains(where: {
            $0.id != game.id && $0.name.caseInsensitiveCompare(game.name) == .orderedSame
        }) {
            throw CatalogError.duplicateName(game.name)
        }
        snapshot.games[index] = game
        try persist()
    }

    public func delete(id: UUID) throws {
        guard let index = snapshot.games.firstIndex(where: { $0.id == id }) else {
            throw CatalogError.notFound(id)
        }
        snapshot.games.remove(at: index)
        snapshot.favorites.removeAll { $0 == id }
        snapshot.recentlyViewed.removeAll { $0 == id }
        try persist()
    }

    public func setFavorite(_ id: UUID, isFavorite: Bool) throws {
        guard snapshot.games.contains(where: { $0.id == id }) else { throw CatalogError.notFound(id) }
        if isFavorite {
            if !snapshot.favorites.contains(id) { snapshot.favorites.append(id) }
        } else {
            snapshot.favorites.removeAll { $0 == id }
        }
        try persist()
    }

    public func recordView(_ id: UUID) throws {
        guard snapshot.games.contains(where: { $0.id == id }) else { return }
        snapshot.recentlyViewed.removeAll { $0 == id }
        snapshot.recentlyViewed.insert(id, at: 0)
        if snapshot.recentlyViewed.count > 20 {
            snapshot.recentlyViewed.removeLast(snapshot.recentlyViewed.count - 20)
        }
        try persist()
    }

    /// Installs the seed catalog if this repository was created without one (kept for tests/tools).
    public func installSeed(_ games: [Game]) throws {
        guard !snapshot.didSeed else { return }
        snapshot.games.append(contentsOf: games)
        snapshot.didSeed = true
        try persist()
    }

    // MARK: - Persistence

    private func persist() throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw CatalogError.persistence(error.localizedDescription)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
