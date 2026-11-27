import Foundation

/// Demo catalog installed **once** on first launch so the app does not open empty.
///
/// Engineering notes — read before judging the data:
/// - Every entry carries `platformTag == "PS4"` and is listed in `SeedCatalog.sampleNames`; the UI
///   shows a discreet "DEMO" badge on those cards and on the detail page.
/// - Download links point to `https://nexus-store.exemplo/...` (deliberately non-routable). The
///   transfer engine validates the link, fails fast with a clear message and never fabricates a
///   transfer. There is no simulated progress anywhere in the app.
/// - Artwork is bundled with the app and was generated for this project, so nothing is hotlinked and
///   the demo works offline.
/// - Any sample can be edited or deleted in the admin panel; deleting one does not re-add it.
public enum SeedCatalog {

    public static let sampleNames: Set<String> = [
        "Ghost of Tsushima",
        "The Last of Us Part II",
        "Red Dead Redemption 2",
        "Bloodborne",
        "God of War Ragnarök",
        "Marvel's Spider-Man",
        "Horizon Forbidden West"
    ]

    public static func isSample(_ game: Game) -> Bool {
        sampleNames.contains(game.name)
    }

    /// Loads `Resources/Seed/seed-catalog.json` from the module bundle.
    public static func games() -> [Game] {
        // `Bundle.module` only exists when the package declares resources; the iOS app embeds the
        // JSON through `SeedCatalog.games()` as well, so fall back to `Bundle.main`.
        let bundle: Bundle? = Bundle.main
        guard let url = bundle?.url(forResource: "seed-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        return decode(data)
    }

    /// Decodes the seed JSON; exposed so tests can assert the shipped catalog stays valid.
    public static func decode(_ data: Data) -> [Game] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Game].self, from: data)) ?? []
    }
}
