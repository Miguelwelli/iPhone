import Foundation

/// File-backed storage for assistant history and settings.
///
/// Archives are capped so the JSON file cannot grow without bound; the most recent searches are kept
/// (50 by default), which is far more than the review screen needs.
public final class AutoCatalogRepository {

    public private(set) var snapshot: AutoCatalogStoreSnapshot
    public let fileURL: URL
    private let fileManager: FileManager
    private let maxSearches: Int

    public init(fileURL: URL, fileManager: FileManager = .default, maxSearches: Int = 50) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.maxSearches = maxSearches
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AutoCatalogStoreSnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = AutoCatalogStoreSnapshot()
        }
    }

    public var searches: [AutoCatalogSearch] { snapshot.searches }
    public var configuration: AutoCatalogConfiguration { snapshot.configuration }

    public func upsert(_ search: AutoCatalogSearch) {
        if let index = snapshot.searches.firstIndex(where: { $0.id == search.id }) {
            snapshot.searches[index] = search
        } else {
            snapshot.searches.insert(search, at: 0)
        }
        if snapshot.searches.count > maxSearches {
            snapshot.searches = Array(snapshot.searches.prefix(maxSearches))
        }
        persist()
    }

    public func delete(searchID: UUID) {
        snapshot.searches.removeAll { $0.id == searchID }
        persist()
    }

    public func clearHistory() {
        snapshot.searches.removeAll()
        persist()
    }

    public func updateConfiguration(_ configuration: AutoCatalogConfiguration) {
        snapshot.configuration = configuration
        persist()
    }

    public func search(id: UUID) -> AutoCatalogSearch? {
        snapshot.searches.first { $0.id == id }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // History is convenience data; losing it must never break the catalog itself.
            assertionFailure("Falha ao salvar histórico do assistente: \(error)")
        }
    }
}
