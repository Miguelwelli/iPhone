import Foundation

/// Approval rules for assistant candidates.
///
/// Lives in the core (not in a SwiftUI store) so CI can exercise the exact code path that writes to
/// the catalog: deduplication, blocking issues, and the transition approved/rejected.
public struct CatalogIngestion {

    public struct CandidateUpdate: Equatable, Sendable {
        public var candidateID: UUID
        public var state: CatalogCandidate.ReviewState
        public var catalogGameID: UUID?
    }

    public enum Outcome: Equatable, Sendable {
        case approved(game: Game)
        case rejected(reason: String)

        public var game: Game? {
            if case .approved(let game) = self { return game }
            return nil
        }
    }

    private let repository: CatalogRepository

    public init(repository: CatalogRepository) {
        self.repository = repository
    }

    /// Adds one candidate to the catalog.
    ///
    /// Fails (without touching the catalog) when the candidate is not pending, has blocking issues,
    /// or duplicates a game that is already registered.
    public func approve(_ candidate: CatalogCandidate) -> Result<Game, CatalogError> {
        guard candidate.state == .pending else {
            return .failure(.duplicateName(candidate.title))
        }
        let issues = candidate.blockingIssues()
        guard issues.isEmpty else {
            return .failure(.persistence(issues.joined(separator: " ")))
        }
        if repository.games.contains(where: { TitleNormalizer.areEquivalent($0.name, candidate.title) }) {
            return .failure(.duplicateName(candidate.title))
        }
        let game = candidate.makeDraft().makeGame()
        do {
            try repository.add(game)
            return .success(game)
        } catch let error as CatalogError {
            return .failure(error)
        } catch {
            return .failure(.persistence(error.localizedDescription))
        }
    }

    /// Approves every pending, ready candidate.
    /// - Returns: the per-candidate updates plus how many were skipped and why.
    public func approveAll(in search: AutoCatalogSearch) -> (updates: [CandidateUpdate], skipped: Int) {
        var updates: [CandidateUpdate] = []
        var skipped = 0
        for candidate in search.candidates where candidate.state == .pending {
            switch approve(candidate) {
            case .success(let game):
                updates.append(CandidateUpdate(candidateID: candidate.id, state: .approved, catalogGameID: game.id))
            case .failure:
                skipped += 1
            }
        }
        return (updates, skipped)
    }

    public func reject(candidateID: UUID) -> CandidateUpdate {
        CandidateUpdate(candidateID: candidateID, state: .rejected, catalogGameID: nil)
    }
}
