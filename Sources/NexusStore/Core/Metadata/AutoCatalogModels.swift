import Foundation

/// What the admin asks the assistant for.
public struct AutoCatalogRequest: Codable, Equatable, Sendable {
    public var categories: [String]
    public var quantity: Int
    public var extractArtwork: Bool

    public init(categories: [String], quantity: Int = 5, extractArtwork: Bool = true) {
        self.categories = categories
        self.quantity = max(1, min(quantity, 20))
        self.extractArtwork = extractArtwork
    }
}

/// Where a proposed value came from.
public struct MetadataSource: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var urlString: String

    public var id: String { name + "|" + urlString }

    public init(name: String, urlString: String) {
        self.name = name
        self.urlString = urlString
    }
}

/// One game the assistant proposes for the catalog, kept separate from `Game` until approved.
public struct CatalogCandidate: Codable, Equatable, Identifiable, Sendable {
    public enum ReviewState: String, Codable, Sendable {
        case pending, approved, rejected
    }

    public var id: UUID
    public var title: String
    public var summary: String
    public var categories: [String]
    public var sizeText: String
    public var version: String
    public var platformTag: String
    public var developer: String
    public var publisher: String
    public var ageRating: String
    public var tags: [String]
    public var coverURLString: String
    public var bannerURLString: String
    public var downloadURLString: String
    public var pkgStatus: PKGLinkStatus
    public var sources: [MetadataSource]
    public var rating: Double
    public var ratingCount: Int
    public var state: ReviewState
    /// Set when approval added the game to the catalog.
    public var catalogGameID: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        categories: [String] = [],
        sizeText: String = "",
        version: String = "",
        platformTag: String = "PS4",
        developer: String = "",
        publisher: String = "",
        ageRating: String = "",
        tags: [String] = [],
        coverURLString: String = "",
        bannerURLString: String = "",
        downloadURLString: String = "",
        pkgStatus: PKGLinkStatus = .notProvided,
        sources: [MetadataSource] = [],
        rating: Double = 0,
        ratingCount: Int = 0,
        state: ReviewState = .pending,
        catalogGameID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.categories = categories
        self.sizeText = sizeText
        self.version = version
        self.platformTag = platformTag
        self.developer = developer
        self.publisher = publisher
        self.ageRating = ageRating
        self.tags = tags
        self.coverURLString = coverURLString
        self.bannerURLString = bannerURLString
        self.downloadURLString = downloadURLString
        self.pkgStatus = pkgStatus
        self.sources = sources
        self.rating = rating
        self.ratingCount = ratingCount
        self.state = state
        self.catalogGameID = catalogGameID
    }

    /// Fields the admin must fix before the game can be registered, mirroring `GameDraft.validate`.
    public func blockingIssues() -> [String] {
        var issues: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            issues.append("Nome ausente.")
        }
        if categories.isEmpty {
            issues.append("Sem categoria.")
        }
        if ByteFormatting.parseSize(sizeText) == nil {
            issues.append(sizeText.isEmpty ? "Tamanho não informado." : "Tamanho inválido.")
        }
        if !downloadURLString.isEmpty && !pkgStatus.isVerified {
            issues.append("Link PKG precisa ser verificado.")
        }
        return issues
    }

    public var isReady: Bool { blockingIssues().isEmpty }

    /// Converts the approved candidate into the catalog's own draft type.
    public func makeDraft() -> GameDraft {
        var draft = GameDraft()
        draft.name = title
        draft.description = summary
        draft.categories = categories
        draft.sizeText = sizeText
        draft.version = version
        draft.downloadURLString = downloadURLString
        draft.coverURLString = coverURLString
        draft.bannerURLString = bannerURLString
        draft.developer = developer
        draft.publisher = publisher
        draft.ageRating = ageRating
        draft.platformTag = platformTag.isEmpty ? "PS4" : platformTag
        draft.tagsText = tags.joined(separator: ", ")
        return draft
    }
}

/// A finished assistant run, stored so the admin can revisit or repeat it.
public struct AutoCatalogSearch: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var request: AutoCatalogRequest
    public var startedAt: Date
    public var finishedAt: Date?
    public var providerName: String
    public var errorMessage: String?
    public var candidates: [CatalogCandidate]

    public init(
        id: UUID = UUID(),
        request: AutoCatalogRequest,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        providerName: String = "",
        errorMessage: String? = nil,
        candidates: [CatalogCandidate] = []
    ) {
        self.id = id
        self.request = request
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.providerName = providerName
        self.errorMessage = errorMessage
        self.candidates = candidates
    }

    public var foundCount: Int { candidates.count }
    public var readyCount: Int { candidates.filter { $0.isReady && $0.state == .pending }.count }
    public var pendingCount: Int { candidates.filter { $0.state == .pending }.count }
    public var approvedCount: Int { candidates.filter { $0.state == .approved }.count }
    public var rejectedCount: Int { candidates.filter { $0.state == .rejected }.count }
    public var isFinished: Bool { finishedAt != nil || errorMessage != nil }
}

/// Everything persisted by the assistant (searches + settings, minus the API key which lives in the
/// Keychain).
public struct AutoCatalogStoreSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var searches: [AutoCatalogSearch]
    public var configuration: AutoCatalogConfiguration

    public init(
        schemaVersion: Int = AutoCatalogStoreSnapshot.currentSchemaVersion,
        searches: [AutoCatalogSearch] = [],
        configuration: AutoCatalogConfiguration = AutoCatalogConfiguration()
    ) {
        self.schemaVersion = schemaVersion
        self.searches = searches
        self.configuration = configuration
    }

    public static let currentSchemaVersion = 1
}

/// Provider/model selection and per-run behaviour. Contains no secret.
public struct AutoCatalogConfiguration: Codable, Equatable, Sendable {
    public enum Model: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Structured game database. Best for covers, genres and publisher, with a verifiable page.
        case rawg
        /// Gemini grounded with Google Search. Best for web coverage; every game carries citations.
        case gemini

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .rawg: return "RAWG — banco de dados de jogos"
            case .gemini: return "Google Gemini + Pesquisa Google"
            }
        }

        public var subtitle: String {
            switch self {
            case .rawg: return "Metadados estruturados • capas • PS4"
            case .gemini: return "Pesquisa na web com citações • capas"
            }
        }

        public var credentialName: String {
            switch self {
            case .rawg: return "Chave RAWG"
            case .gemini: return "Chave Google AI (Gemini)"
            }
        }

        /// Where the admin gets a key for this provider.
        public var credentialHelpURLString: String {
            switch self {
            case .rawg: return "https://rawg.io/apikey"
            case .gemini: return "https://aistudio.google.com/apikey"
            }
        }

        /// Keychain account used for this provider's credential.
        public var credentialAccount: String {
            switch self {
            case .rawg: return "rawg-api-key"
            case .gemini: return "gemini-api-key"
            }
        }
    }

    public var model: Model
    /// Default category pre-selected on the search screen.
    public var defaultCategories: [String]
    public var defaultQuantity: Int
    public var extractArtwork: Bool
    /// Verifies the .pkg link with a real HTTP request before approving.
    public var verifyPKGLinks: Bool

    public init(
        model: Model = .rawg,
        defaultCategories: [String] = [],
        defaultQuantity: Int = 5,
        extractArtwork: Bool = true,
        verifyPKGLinks: Bool = true
    ) {
        self.model = model
        self.defaultCategories = defaultCategories
        self.defaultQuantity = defaultQuantity
        self.extractArtwork = extractArtwork
        self.verifyPKGLinks = verifyPKGLinks
    }
}
