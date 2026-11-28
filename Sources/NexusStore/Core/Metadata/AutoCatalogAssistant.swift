import Foundation

/// Builds catalog candidates from real metadata results.
///
/// The assistant is deliberately "dumb" about truth: it maps only what the provider returned, marks
/// every link as untested unless a real HTTP check ran, and drops anything that duplicates the
/// catalog. All the intelligence lives in the provider; this type owns the rules.
public struct AutoCatalogAssistant: Sendable {

    private let provider: MetadataProvider
    private let verifier: PKGLinkVerifier

    public init(provider: MetadataProvider, verifier: PKGLinkVerifier = PKGLinkVerifier()) {
        self.provider = provider
        self.verifier = verifier
    }

    public struct Outcome: Sendable {
        public var candidates: [CatalogCandidate]
        public var duplicatesSkipped: Int
        public var providerName: String
    }

    /// Runs the search and prepares the review list.
    /// - Parameters:
    ///   - request: categories, quantity, artwork flag.
    ///   - existingGames: the real catalog, used for duplicate control.
    ///   - knownPKGLinks: admin-supplied links keyed by normalized title (the provider never invents them).
    public func run(
        request: AutoCatalogRequest,
        existingGames: [Game],
        knownPKGLinks: [String: String] = [:],
        verifyLinks: Bool = true
    ) async throws -> Outcome {
        let query = MetadataQuery(
            categories: request.categories,
            limit: request.quantity,
            excludedTitles: existingGames.map(\.name)
        )
        let response = try await provider.search(query)
        let results = response.items

        var duplicates = response.duplicatesSkipped
        var candidates: [CatalogCandidate] = []
        for result in results {
            let isDuplicate = existingGames.contains { TitleNormalizer.areEquivalent($0.name, result.title) }
                || candidates.contains { TitleNormalizer.areEquivalent($0.title, result.title) }
            if isDuplicate {
                duplicates += 1
                continue
            }

            var candidate = CatalogCandidate(
                title: result.title,
                summary: result.summary,
                categories: Self.mapCategories(result.genres, requested: request.categories),
                sizeText: result.sizeText,
                version: result.version,
                platformTag: "PS4",
                developer: result.developer,
                publisher: result.publisher,
                ageRating: result.ageRating,
                tags: result.tags,
                coverURLString: request.extractArtwork ? result.coverURLString : "",
                bannerURLString: request.extractArtwork ? Self.banner(for: result) : "",
                downloadURLString: knownPKGLinks[TitleNormalizer.normalize(result.title)] ?? "",
                sources: [MetadataSource(name: result.sourceName, urlString: result.sourceURLString)]
            )

            if candidate.downloadURLString.isEmpty {
                candidate.pkgStatus = .notProvided
            } else if verifyLinks {
                candidate.pkgStatus = await verifier.verify(candidate.downloadURLString)
            } else {
                candidate.pkgStatus = .notChecked("Verificação automática desativada nos ajustes.")
            }
            candidates.append(candidate)
        }

        return Outcome(candidates: candidates, duplicatesSkipped: duplicates, providerName: provider.displayName)
    }

    /// Maps provider genres onto the store's categories, falling back to the requested ones.
    public static func mapCategories(_ genres: [String], requested: [String]) -> [String] {
        // Keywords are matched against RAWG genre names *and* slugs (both are passed in), plus tags.
        let rules: [(String, [String])] = [
            ("acao", ["action"]),
            ("aventura", ["adventure"]),
            ("rpg", ["rpg", "role-playing"]),
            ("tiro", ["shooter", "fps"]),
            ("mundo-aberto", ["open world", "open-world"]),
            ("esportes", ["sports"]),
            ("corrida", ["racing"]),
            ("terror", ["horror"]),
            ("estrategia", ["strategy"]),
            ("simulacao", ["simulation"]),
            ("luta", ["fighting"]),
            ("familia", ["family", "party"]),
            ("soulslike", ["souls", "souls-like"])
        ]
        let lowered = genres.map { $0.lowercased() }
        var matched: [String] = []
        for (category, keywords) in rules {
            if lowered.contains(where: { genre in keywords.contains(where: { genre.contains($0) }) }) {
                matched.append(category)
            }
        }
        return matched.isEmpty ? Array(requested.prefix(1)) : Array(Set(matched)).sorted()
    }

    /// RAWG's additional image is landscape; when it is missing the cover is used as banner so the
    /// card still renders artwork the source actually returned.
    private static func banner(for result: MetadataCandidate) -> String {
        if !result.bannerURLString.isEmpty { return result.bannerURLString }
        return result.coverURLString
    }
}
