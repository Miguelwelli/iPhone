import Foundation

struct Game: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var cover_url: String
    var banner_url: String?
    var description: String
    var category: String
    var platform: String
    var size: String
    var download_url: String
    var published: Bool
    var created_at: Date
    var updated_at: Date

    init(
        id: UUID = UUID(),
        name: String,
        cover_url: String,
        banner_url: String? = nil,
        description: String,
        category: String,
        platform: String = "PS4",
        size: String,
        download_url: String,
        published: Bool = true,
        created_at: Date = Date(),
        updated_at: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.cover_url = cover_url
        self.banner_url = banner_url
        self.description = description
        self.category = category
        self.platform = platform
        self.size = size
        self.download_url = download_url
        self.published = published
        self.created_at = created_at
        self.updated_at = updated_at
    }
}

enum GameCategory: String, CaseIterable, Identifiable {
    case action = "Ação"
    case adventure = "Aventura"
    case rpg = "RPG"
    case sports = "Esportes"
    case racing = "Corrida"
    case fighting = "Luta"
    case horror = "Terror"
    case indie = "Indie"
    case shooter = "Tiro"
    case simulation = "Simulação"

    var id: String { rawValue }
}

enum GamePlatform: String, CaseIterable, Identifiable {
    case ps4 = "PS4"
    case ps4Pro = "PS4 Pro"
    case ps4Homebrew = "PS4 Homebrew"

    var id: String { rawValue }
}

struct SupabaseConfig: Codable, Equatable, Sendable {
    var projectURL: String
    var anonKey: String
    var accessToken: String

    var isConfigured: Bool {
        !projectURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var normalizedURL: String {
        var url = projectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") {
            url.removeLast()
        }
        return url
    }
}
