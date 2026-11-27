import Foundation

/// A game candidate returned by an external metadata source.
///
/// Every field is optional or empty when the source did not return it. The assistant never invents
/// values: whatever is missing here stays missing in the review screen and in the final game record.
public struct MetadataCandidate: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var releaseDate: Date?
    public var genres: [String]
    /// Cover URL exactly as returned by the source (https only).
    public var coverURLString: String
    /// Landscape artwork URL when the source offers one.
    public var bannerURLString: String
    public var platforms: [String]
    /// Size reported by the source, already formatted ("48.5 GB") or empty.
    public var sizeText: String
    public var version: String
    public var developer: String
    public var publisher: String
    public var ageRating: String
    public var tags: [String]
    public var rating: Double
    public var ratingCount: Int
    /// Human readable provenance, e.g. "RAWG (rawg.io)".
    public var sourceName: String
    /// Canonical page for the record, so the admin can check every field.
    public var sourceURLString: String

    public init(
        id: String,
        title: String,
        summary: String = "",
        releaseDate: Date? = nil,
        genres: [String] = [],
        coverURLString: String = "",
        bannerURLString: String = "",
        platforms: [String] = ["PS4"],
        sizeText: String = "",
        version: String = "",
        developer: String = "",
        publisher: String = "",
        ageRating: String = "",
        tags: [String] = [],
        rating: Double = 0,
        ratingCount: Int = 0,
        sourceName: String,
        sourceURLString: String = ""
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.releaseDate = releaseDate
        self.genres = genres
        self.coverURLString = coverURLString
        self.bannerURLString = bannerURLString
        self.platforms = platforms
        self.sizeText = sizeText
        self.version = version
        self.developer = developer
        self.publisher = publisher
        self.ageRating = ageRating
        self.tags = tags
        self.rating = rating
        self.ratingCount = ratingCount
        self.sourceName = sourceName
        self.sourceURLString = sourceURLString
    }
}

/// A query sent to a metadata source.
public struct MetadataQuery: Equatable, Sendable {
    public var categories: [String]
    public var limit: Int
    /// Titles that already exist in the catalog; providers must not return them again.
    public var excludedTitles: [String]
    /// Free text used by sources that support searching.
    public var searchTerms: String

    public init(
        categories: [String],
        limit: Int,
        excludedTitles: [String] = [],
        searchTerms: String = ""
    ) {
        self.categories = categories
        self.limit = max(1, min(limit, 30))
        self.excludedTitles = excludedTitles
        self.searchTerms = searchTerms
    }
}

public enum MetadataProviderError: LocalizedError, Equatable, Sendable {
    case missingCredential
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case network(String)
    case invalidResponse
    case server(status: Int)

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Nenhuma chave de API configurada. Abra a configuração e informe a chave."
        case .unauthorized:
            return "Chave de API recusada pelo servidor (401). Verifique se ela está correta e ativa."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Limite de requisições atingido. Tente novamente em \(retryAfter) segundos."
            }
            return "Limite de requisições atingido. Tente novamente em alguns minutos."
        case .network(let message):
            return "Falha de rede: \(message)"
        case .invalidResponse:
            return "O servidor respondeu em um formato inesperado."
        case .server(let status):
            return "O servidor respondeu com erro HTTP \(status)."
        }
    }
}

/// Result of a provider search: the new candidates plus the titles the provider discarded because they
/// were duplicates. Reporting the count keeps the UI honest ("3 duplicados ignorados").
public struct MetadataSearchResult: Sendable, Equatable {
    public var items: [MetadataCandidate]
    public var duplicatesSkipped: Int

    public init(items: [MetadataCandidate], duplicatesSkipped: Int = 0) {
        self.items = items
        self.duplicatesSkipped = duplicatesSkipped
    }
}

/// Contract implemented by every metadata source (RAWG today; adding another source means adding a
/// type, not touching the screens).
public protocol MetadataProvider: Sendable {
    var displayName: String { get }
    /// Cheap call that validates credentials and reports latency.
    func testConnection() async throws -> TimeInterval
    func search(_ query: MetadataQuery) async throws -> MetadataSearchResult
}
