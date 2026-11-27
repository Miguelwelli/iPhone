import Foundation

/// A game in the Nexus Store catalog.
///
/// The model is intentionally dependency-free (`Foundation` only) so it can be shared between the
/// iOS app and Linux CI tests. Persistence is handled by `JSONStore` (see `CatalogStore.swift`).
///
/// Every value that the admin can type is stored verbatim *and* a set of computed helpers exposes
/// normalized/validated views (`byteCount`, `downloadURL`, `searchableText`...) so the UI never has
/// to re-implement parsing rules.
public struct Game: Identifiable, Codable, Hashable, Sendable {

    /// Stable identifier. Generated with `UUID()` for new games and preserved forever after that.
    public var id: UUID
    public var name: String
    public var description: String
    /// Category identifiers (raw values of `GameCategory`). A game can belong to more than one.
    public var categories: [String]
    /// Size as typed by the admin, e.g. "48.5 GB". Parsing is done by `ByteFormatting`.
    public var sizeText: String
    public var version: String
    /// HTTPS link to the .pkg file.
    public var downloadURLString: String
    /// HTTPS link to the cover art (2:3 portrait).
    public var coverURLString: String
    /// HTTPS link to the banner art (16:9 landscape).
    public var bannerURLString: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isFeatured: Bool
    /// Free-form platform tag shown on cards ("PS4", "PS4 ENHANCED"...).
    public var platformTag: String
    /// Optional developer / publisher / age rating metadata, shown on the detail page.
    public var developer: String
    public var publisher: String
    public var ageRating: String
    /// Aggregate rating (0...5). Zero means "not rated".
    public var rating: Double
    public var ratingCount: Int
    /// Bonus attributes shown on the detail page ("1 Jogador", "PT-BR", "HDR"...).
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        categories: [String] = [],
        sizeText: String = "",
        version: String = "",
        downloadURLString: String = "",
        coverURLString: String = "",
        bannerURLString: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFeatured: Bool = false,
        platformTag: String = "PS4",
        developer: String = "",
        publisher: String = "",
        ageRating: String = "",
        rating: Double = 0,
        ratingCount: Int = 0,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.categories = categories
        self.sizeText = sizeText
        self.version = version
        self.downloadURLString = downloadURLString
        self.coverURLString = coverURLString
        self.bannerURLString = bannerURLString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFeatured = isFeatured
        self.platformTag = platformTag
        self.developer = developer
        self.publisher = publisher
        self.ageRating = ageRating
        self.rating = rating
        self.ratingCount = ratingCount
        self.tags = tags
    }
}

// MARK: - Derived values

public extension Game {

    /// Parsed byte count of `sizeText`. Zero when the text cannot be parsed.
    var byteCount: Int64 { ByteFormatting.parseSize(sizeText) ?? 0 }

    var downloadURL: URL? { HTTPSURLValidator.url(from: downloadURLString) }
    var coverURL: URL? { HTTPSURLValidator.url(from: coverURLString) }
    var bannerURL: URL? { HTTPSURLValidator.url(from: bannerURLString) }
    var coverArtwork: ArtworkReference { ArtworkReference(rawValue: coverURLString) }
    var bannerArtwork: ArtworkReference { ArtworkReference(rawValue: bannerURLString) }

    /// Categories resolved against the built-in catalog. Unknown raw values are ignored.
    var resolvedCategories: [GameCategory] {
        categories.compactMap(GameCategory.init(rawValue:))
    }

    /// Human readable category line ("Ação · Mundo Aberto").
    var categoryLine: String {
        let names = resolvedCategories.map(\.title)
        return names.isEmpty ? "Sem categoria" : names.joined(separator: " · ")
    }

    /// Text used by the search screen: name, description, categories, developer and publisher, folded
    /// for diacritic/case insensitive matching.
    var searchableText: String {
        SearchText.fold([name, description, developer, publisher, platformTag]
            .joined(separator: " ") + " " + categoryLine)
    }

    /// File name used on the console. Falls back to a slug of the name plus the .pkg extension.
    var remotePackageName: String {
        if let url = downloadURL {
            return HTTPSURLValidator.suggestedFileName(for: url, fallback: Self.slug(name) + ".pkg")
        }
        return Self.slug(name) + ".pkg"
    }

    static func slug(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        var output = ""
        for character in folded.unicodeScalars {
            if allowed.contains(character) {
                output.unicodeScalars.append(character)
            } else if !output.hasSuffix("-") {
                output.append("-")
            }
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    var ratingText: String {
        guard rating > 0 else { return "—" }
        return String(format: "%.1f", rating)
    }

    /// "18.4K" style compact count.
    var ratingCountText: String {
        guard ratingCount > 0 else { return "" }
        if ratingCount >= 1000 {
            let compact = Double(ratingCount) / 1000.0
            return String(format: "%.1fK", compact)
        }
        return "\(ratingCount)"
    }
}

// MARK: - Draft (used by the admin form before validation/conversion)

/// A mutable, all-strings representation of a game used by the admin form.
///
/// Keeping the draft as a value type makes validation pure and testable: `GameDraft.validate()`
/// returns every problem at once (so the form can show field-level errors) and `makeGame(...)`
/// only exists after validation passes.
public struct GameDraft: Equatable, Sendable {
    public var name: String = ""
    public var description: String = ""
    public var categories: [String] = []
    public var sizeText: String = ""
    public var version: String = ""
    public var downloadURLString: String = ""
    public var coverURLString: String = ""
    public var bannerURLString: String = ""
    public var developer: String = ""
    public var publisher: String = ""
    public var ageRating: String = ""
    public var platformTag: String = "PS4"
    public var isFeatured: Bool = false
    public var tagsText: String = ""

    public init() {}

    public init(game: Game) {
        name = game.name
        description = game.description
        categories = game.categories
        sizeText = game.sizeText
        version = game.version
        downloadURLString = game.downloadURLString
        coverURLString = game.coverURLString
        bannerURLString = game.bannerURLString
        developer = game.developer
        publisher = game.publisher
        ageRating = game.ageRating
        platformTag = game.platformTag
        isFeatured = game.isFeatured
        tagsText = game.tags.joined(separator: ", ")
    }

    /// Validates the draft.
    /// - Parameter knownCategories: raw values accepted for `categories`.
    /// - Returns: a dictionary of field key -> message. Empty when the draft is valid.
    public func validate(knownCategories: [String] = GameCategory.allRawValues) -> [GameField: String] {
        var errors: [GameField: String] = [:]

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errors[.name] = "Informe o nome do jogo."
        } else if trimmedName.count < 2 {
            errors[.name] = "O nome precisa de pelo menos 2 caracteres."
        }

        if categories.isEmpty {
            errors[.categories] = "Selecione ao menos uma categoria."
        } else if !categories.allSatisfy({ knownCategories.contains($0) }) {
            errors[.categories] = "Categoria desconhecida."
        }

        if sizeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.size] = "Informe o tamanho (ex.: 48.5 GB)."
        } else if ByteFormatting.parseSize(sizeText) == nil {
            errors[.size] = "Tamanho inválido. Use um formato como 48.5 GB ou 900 MB."
        }

        if downloadURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.downloadURL] = "Informe o link HTTPS do arquivo PKG."
        } else if HTTPSURLValidator.validate(downloadURLString, requiringPKG: true) != nil {
            errors[.downloadURL] = HTTPSURLValidator.validate(downloadURLString, requiringPKG: true)?.message
        }

        // Artwork may be a https URL or the name of a bundled asset (demo catalog).
        if !coverURLString.isEmpty, !ArtworkReference(rawValue: coverURLString).isValid {
            errors[.cover] = "Capa inválida. Use um link HTTPS de imagem."
        }
        if !bannerURLString.isEmpty, !ArtworkReference(rawValue: bannerURLString).isValid {
            errors[.banner] = "Banner inválido. Use um link HTTPS de imagem."
        }

        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedVersion.isEmpty {
            errors[.version] = "Informe a versão (ex.: 1.05)."
        }
        return errors
    }

    public var isValid: Bool { validate().isEmpty }

    /// Builds a `Game` from a validated draft.
    public func makeGame(existing: Game? = nil, now: Date = Date(), newID: UUID = UUID()) -> Game {
        let trimmed = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Game(
            id: existing?.id ?? newID,
            name: trimmed(name),
            description: trimmed(description),
            categories: categories,
            sizeText: trimmed(sizeText),
            version: trimmed(version),
            downloadURLString: trimmed(downloadURLString),
            coverURLString: trimmed(coverURLString),
            bannerURLString: trimmed(bannerURLString),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            isFeatured: isFeatured,
            platformTag: trimmed(platformTag).isEmpty ? "PS4" : trimmed(platformTag),
            developer: trimmed(developer),
            publisher: trimmed(publisher),
            ageRating: trimmed(ageRating),
            rating: existing?.rating ?? 0,
            ratingCount: existing?.ratingCount ?? 0,
            tags: trimmed(tagsText)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }
}

/// Field identifiers for form validation errors.
public enum GameField: String, Hashable, Sendable, CaseIterable {
    case name, categories, size, version, downloadURL, cover, banner
}
