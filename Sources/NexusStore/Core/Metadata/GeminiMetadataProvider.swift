import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Metadata source backed by **Google Gemini grounded with Google Search**.
///
/// How it works (Google AI for Developers, `generateContent` API):
/// - `tools: [{ "google_search": {} }]` lets the model run real web searches and return
///   `groundingMetadata` with the URLs it used;
/// - `generationConfig.responseMimeType = application/json` plus a response schema makes the answer
///   machine readable instead of free prose;
/// - `x-goog-api-key` carries the admin's own key (never bundled in the app).
///
/// Honesty rules enforced here:
/// - a game **must** come back with at least one citation URL, otherwise it is discarded (the model ran
///   no search, so the data would be memory);
/// - `packageSize` is only kept when Gemini researched it *and* cited a source; if the model cannot
///   ground it, the field stays empty and the review screen asks the admin to fill it;
/// - no `.pkg` link is ever produced: the model is explicitly told not to, and links only come from the
///   admin (verified by `PKGLinkVerifier`).
public struct GeminiMetadataProvider: MetadataProvider {

    public let displayName = "Gemini (Google Search)"

    /// Models that support the `google_search` grounding tool. Newest first; unknown values are
    /// passed through so a key with access to a newer model keeps working.
    public static let supportedModels = ["gemini-3.5-flash", "gemini-2.5-flash", "gemini-2.0-flash"]

    public static let apiBaseURLString = "https://generativelanguage.googleapis.com/v1beta"
    public static let defaultModel = "gemini-3.5-flash"

    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, model: String = GeminiMetadataProvider.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? Self.defaultModel : model
        self.session = session
    }

    // MARK: - Connection test

    public func testConnection() async throws -> TimeInterval {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MetadataProviderError.missingCredential }
        let start = Date()
        let body: [String: Any] = [
            "contents": [["parts": [["text": "Responda apenas: ok"]]]],
            "generationConfig": ["maxOutputTokens": 8, "temperature": 0]
        ]
        _ = try await postGenerate(body: body)
        return Date().timeIntervalSince(start)
    }

    // MARK: - Search

    public func search(_ query: MetadataQuery) async throws -> MetadataSearchResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MetadataProviderError.missingCredential }

        let wanted = max(query.limit, 1)
        let excluded = query.excludedTitles.prefix(40).joined(separator: "; ")
        let categories = query.categories.map { GameCategory.title(for: $0) }.joined(separator: ", ")

        let prompt = """
        Você é um assistente de catálogo de jogos de PlayStation 4.

        Tarefa: pesquise na web e encontre \(wanted) jogos de PS4 reais nas categorias: \(categories.isEmpty ? "quaisquer" : categories).

        Regras obrigatórias:
        1. Use a Pesquisa Google para confirmar cada jogo. Não use conhecimento de memória.
        2. NÃO invente links de download .pkg. Nunca.
        3. Se não encontrar o tamanho exato do pacote em uma fonte, deixe "packageSize" vazio.
        4. Cada jogo precisa de pelo menos uma URL de fonte que realmente tenha sido citada na pesquisa.
        5. Não repita estes jogos, que já estão no catálogo: \(excluded.isEmpty ? "nenhum" : excluded).
        6. Prefira capas oficiais do jogo certo; a URL deve ser https e acessível.

        Responda SOMENTE com JSON neste formato:
        {"games":[{"title":"","description":"","categories":["Ação / Aventura"],"publisher":"","developer":"","releaseYear":"","packageSize":"","version":"","coverURL":"","bannerURL":"","sourceURLs":["https://..."]}]}
        """

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "tools": [["google_search": [:] as [String: Any]]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json",
                "responseSchema": Self.responseSchema
            ]
        ]

        let json = try await postGenerate(body: body)
        let (items, droppedWithoutCitation) = Self.parse(json: json, requestedCategories: query.categories, limit: wanted)
        return MetadataSearchResult(items: items, duplicatesSkipped: droppedWithoutCitation)
    }

    // MARK: - Response schema

    /// Keeps the model inside the shape the app understands.
    static let responseSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "games": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "title": ["type": "STRING"],
                        "description": ["type": "STRING"],
                        "categories": ["type": "ARRAY", "items": ["type": "STRING"]],
                        "publisher": ["type": "STRING"],
                        "developer": ["type": "STRING"],
                        "releaseYear": ["type": "STRING"],
                        "packageSize": ["type": "STRING"],
                        "version": ["type": "STRING"],
                        "coverURL": ["type": "STRING"],
                        "bannerURL": ["type": "STRING"],
                        "sourceURLs": ["type": "ARRAY", "items": ["type": "STRING"]]
                    ],
                    "required": ["title", "sourceURLs"]
                ]
            ]
        ],
        "required": ["games"]
    ]

    // MARK: - Parsing

    /// Extracts candidates from a `generateContent` response.
    /// - Returns: the usable candidates and how many were discarded for lacking a grounding citation.
    static func parse(json: [String: Any], requestedCategories: [String], limit: Int) -> ([MetadataCandidate], Int) {
        guard let text = firstText(in: json),
              let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let games = root["games"] as? [[String: Any]] else {
            return ([], 0)
        }

        // Every URL Gemini actually cited (from groundingMetadata), used to validate sourceURLs.
        let citedURLs = Set(groundingURLs(in: json))

        var candidates: [MetadataCandidate] = []
        var dropped = 0
        for game in games {
            guard let title = (game["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  title.count >= 2 else { continue }

            let declaredSources = (game["sourceURLs"] as? [String] ?? [])
                .filter { $0.lowercased().hasPrefix("https://") }
            // A source is only accepted when it appears in Gemini's own grounding metadata.
            let verifiedSources = declaredSources.filter { url in
                citedURLs.isEmpty ? false : citedURLs.contains(where: { $0.hasPrefix(url) || url.hasPrefix($0) })
            }
            guard !verifiedSources.isEmpty else {
                // No grounding citation means the "research" is not evidenced: drop it rather than
                // presenting memory as fact.
                dropped += 1
                continue
            }

            let size = (game["packageSize"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let validSize = ByteFormatting.parseSize(size) != nil ? size : ""

            candidates.append(MetadataCandidate(
                id: "gemini-\(TitleNormalizer.normalize(title))",
                title: title,
                summary: (game["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                releaseDate: nil,
                genres: game["categories"] as? [String] ?? [],
                coverURLString: Self.httpsURL(game["coverURL"] as? String),
                bannerURLString: Self.httpsURL(game["bannerURL"] as? String),
                platforms: ["PlayStation 4"],
                sizeText: validSize,
                version: (game["version"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                developer: (game["developer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                publisher: (game["publisher"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                ageRating: "",
                tags: [],
                rating: 0,
                ratingCount: 0,
                sourceName: "Gemini + Google Search",
                sourceURLString: verifiedSources.first ?? ""
            ))
            if candidates.count >= limit { break }
        }
        return (candidates, dropped)
    }

    /// URLs from `groundingMetadata.groundingChunks[].web.uri`.
    static func groundingURLs(in json: [String: Any]) -> [String] {
        guard let candidatesArray = json["candidates"] as? [[String: Any]],
              let first = candidatesArray.first,
              let metadata = first["groundingMetadata"] as? [String: Any],
              let chunks = metadata["groundingChunks"] as? [[String: Any]] else { return [] }
        return chunks.compactMap { chunk in
            (chunk["web"] as? [String: Any])?["uri"] as? String
        }
    }

    static func firstText(in json: [String: Any]) -> String? {
        guard let candidatesArray = json["candidates"] as? [[String: Any]],
              let first = candidatesArray.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    private static func httpsURL(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        if raw.lowercased().hasPrefix("https://") { return raw }
        if raw.lowercased().hasPrefix("http://") { return "https://" + raw.dropFirst("http://".count) }
        return ""
    }

    // MARK: - Transport

    private func postGenerate(body: [String: Any]) async throws -> [String: Any] {
        let urlString = "\(Self.apiBaseURLString)/models/\(model):generateContent"
        guard let url = URL(string: urlString) else { throw MetadataProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 40
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MetadataProviderError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw MetadataProviderError.invalidResponse }
        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw MetadataProviderError.unauthorized
        case 404:
            // Model name not available for this key.
            throw MetadataProviderError.server(status: 404)
        case 429:
            throw MetadataProviderError.rateLimited(retryAfter: nil)
        default:
            throw MetadataProviderError.server(status: http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MetadataProviderError.invalidResponse
        }
        return json
    }
}
