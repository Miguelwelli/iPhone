import Foundation
import SwiftUI

/// State and orchestration for **Assistente IA — Auto-Catálogo**.
///
/// Responsibilities:
/// - keep the metadata API key in the Keychain (never in `UserDefaults`, never in the bundle);
/// - run a real search through `AutoCatalogAssistant` and expose progress/errors;
/// - persist history (`AutoCatalogRepository`) so a search can be revisited or repeated;
/// - approve candidates into the **existing** `CatalogStore` (there is no second catalog).
@MainActor
public final class AutoCatalogStore: ObservableObject {

    public enum Phase: Equatable {
        case idle
        case testing
        case connected(latencyMilliseconds: Int)
        case searching(step: String)
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var history: [AutoCatalogSearch] = []
    @Published public private(set) var configuration: AutoCatalogConfiguration
    @Published public private(set) var hasAPIKey: Bool
    @Published public var lastRunNote: String?

    private let repository: AutoCatalogRepository
    private let keyStore: APIKeyStoring
    private let catalog: CatalogStore
    private let ingestion: CatalogIngestion
    private let sessionFactory: (String) -> URLSession
    /// Admin supplied .pkg links keyed by normalized title. The assistant never invents links.
    private var pkgLinks: [String: String] = [:]

    public init(
        repository: AutoCatalogRepository,
        keyStore: APIKeyStoring,
        catalog: CatalogStore,
        sessionFactory: @escaping (String) -> URLSession = { _ in .shared }
    ) {
        self.repository = repository
        self.keyStore = keyStore
        self.catalog = catalog
        self.ingestion = CatalogIngestion(repository: catalog.repository)
        self.sessionFactory = sessionFactory
        self.history = repository.searches
        self.configuration = repository.configuration
        self.hasAPIKey = !(keyStore.apiKey() ?? "").isEmpty
    }

    // MARK: - Credentials

    public var maskedAPIKey: String {
        guard let key = keyStore.apiKey(), !key.isEmpty else { return "" }
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        return String(key.prefix(4)) + String(repeating: "•", count: max(6, key.count - 8)) + String(key.suffix(4))
    }

    public func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try keyStore.save(trimmed)
            hasAPIKey = !trimmed.isEmpty
            phase = .idle
            if trimmed.isEmpty { lastRunNote = "Chave removida do Keychain." }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func removeAPIKey() {
        keyStore.delete()
        hasAPIKey = false
        phase = .idle
    }

    public func saveConfiguration(_ configuration: AutoCatalogConfiguration) {
        self.configuration = configuration
        repository.updateConfiguration(configuration)
    }

    /// Admin-provided link for a specific title (normalized internally).
    public func setPKGLink(_ link: String, forTitle title: String) {
        pkgLinks[TitleNormalizer.normalize(title)] = link.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Connection test

    public func testConnection() async {
        guard let key = keyStore.apiKey(), !key.isEmpty else {
            phase = .failed(MetadataProviderError.missingCredential.localizedDescription)
            return
        }
        phase = .testing
        do {
            let latency = try await makeProvider(key: key).testConnection()
            phase = .connected(latencyMilliseconds: Int((latency * 1000).rounded()))
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    // MARK: - Search

    @discardableResult
    public func startSearch(
        request: AutoCatalogRequest,
        verifyLinks: Bool = true
    ) async -> AutoCatalogSearch? {
        guard let key = keyStore.apiKey(), !key.isEmpty else {
            phase = .failed(MetadataProviderError.missingCredential.localizedDescription)
            return nil
        }
        phase = .searching(step: "Consultando \(configuration.model.title)…")

        var record = AutoCatalogSearch(request: request, providerName: configuration.model.title)
        repository.upsert(record)

        let assistant = AutoCatalogAssistant(
            provider: makeProvider(key: key),
            verifier: PKGLinkVerifier(session: sessionFactory(key))
        )
        do {
            let outcome = try await assistant.run(
                request: request,
                existingGames: catalog.games,
                knownPKGLinks: pkgLinks,
                verifyLinks: verifyLinks && configuration.verifyPKGLinks
            )
            record.candidates = outcome.candidates
            record.providerName = outcome.providerName
            record.finishedAt = Date()
            repository.upsert(record)
            refreshHistory()
            phase = .idle
            lastRunNote = outcome.duplicatesSkipped > 0
                ? "\(outcome.candidates.count) encontrados • \(outcome.duplicatesSkipped) duplicados ignorados"
                : "\(outcome.candidates.count) encontrados"
            return record
        } catch {
            record.errorMessage = Self.message(for: error)
            record.finishedAt = Date()
            repository.upsert(record)
            refreshHistory()
            phase = .failed(record.errorMessage ?? "Falha desconhecida.")
            return record
        }
    }

    // MARK: - Review actions

    public func update(candidate: CatalogCandidate, in searchID: UUID) {
        mutate(searchID: searchID) { search in
            guard let index = search.candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
            search.candidates[index] = candidate
        }
    }

    public func reject(candidateID: UUID, in searchID: UUID) {
        mutate(searchID: searchID) { search in
            guard let index = search.candidates.firstIndex(where: { $0.id == candidateID }) else { return }
            search.candidates[index].state = .rejected
        }
    }

    /// Approves one candidate into the real catalog.
    @discardableResult
    public func approve(candidateID: UUID, in searchID: UUID) -> Result<Game, CatalogError> {
        guard let search = repository.search(id: searchID),
              let candidate = search.candidates.first(where: { $0.id == candidateID }) else {
            return .failure(.notFound(candidateID))
        }
        return approve(candidate, in: searchID)
    }

    @discardableResult
    public func approve(_ candidate: CatalogCandidate, in searchID: UUID) -> Result<Game, CatalogError> {
        guard candidate.state == .pending else {
            return .failure(.duplicateName(candidate.title))
        }
        switch ingestion.approve(candidate) {
        case .success(let game):
            catalog.reload()
            mutate(searchID: searchID) { search in
                guard let index = search.candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
                search.candidates[index].state = .approved
                search.candidates[index].catalogGameID = game.id
            }
            return .success(game)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Approves every candidate that has no blocking issue. Returns `(approved, skipped)`.
    @discardableResult
    public func approveAll(in searchID: UUID) -> (approved: Int, skipped: Int) {
        guard let search = repository.search(id: searchID) else { return (0, 0) }
        let result = ingestion.approveAll(in: search)
        catalog.reload()
        if !result.updates.isEmpty {
            mutate(searchID: searchID) { stored in
                for update in result.updates {
                    guard let index = stored.candidates.firstIndex(where: { $0.id == update.candidateID }) else { continue }
                    stored.candidates[index].state = update.state
                    stored.candidates[index].catalogGameID = update.catalogGameID
                }
            }
        }
        return (result.updates.count, result.skipped)
    }

    public func recheckPKGLink(for candidate: CatalogCandidate, in searchID: UUID) async {
        guard !candidate.downloadURLString.isEmpty else { return }
        let status = await PKGLinkVerifier(session: sessionFactory("pkg"))
            .verify(candidate.downloadURLString)
        var updated = candidate
        updated.pkgStatus = status
        update(candidate: updated, in: searchID)
    }

    public func delete(searchID: UUID) {
        repository.delete(searchID: searchID)
        refreshHistory()
    }

    public func clearHistory() {
        repository.clearHistory()
        refreshHistory()
    }

    public func search(id: UUID) -> AutoCatalogSearch? { repository.search(id: id) }

    // MARK: - Helpers

    private func mutate(searchID: UUID, _ change: (inout AutoCatalogSearch) -> Void) {
        guard var search = repository.search(id: searchID) else { return }
        change(&search)
        repository.upsert(search)
        refreshHistory()
    }

    private func refreshHistory() {
        history = repository.searches
    }

    private func makeProvider(key: String) -> RAWGMetadataProvider {
        RAWGMetadataProvider(apiKey: key, session: sessionFactory(key))
    }

    public static func message(for error: Error) -> String {
        if let providerError = error as? MetadataProviderError {
            return providerError.localizedDescription
        }
        return error.localizedDescription
    }
}
