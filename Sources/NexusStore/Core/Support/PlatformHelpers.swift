import Foundation

/// Small cross-platform helpers so the core module compiles on Linux CI and iOS unchanged.
public enum PlatformInfo {
    /// "iPhone", "iPad", "Mac" or the OS name on other platforms.
    public static var deviceModel: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(Linux)
        return "Linux"
        #else
        return "Desconhecido"
        #endif
    }

    public static var isIOSLike: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
}

public enum Formatting {
    /// Localized date used in the admin list ("27 nov 2026").
    public static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }

    /// "27/11/2026 14:05"
    public static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }
}

/// Public access point used by the app to load the demo catalog shipped in the app bundle.
public enum DemoCatalogBridge {
    /// Decodes `seed-catalog.json` from the main bundle (the iOS app embeds it as a resource).
    public static func loadFromMainBundle() -> [Game] {
        guard let url = Bundle.main.url(forResource: "seed-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        return CoreJSON.decodeGames(data)
    }
}

public enum CoreJSON {
    public static func decodeGames(_ data: Data) -> [Game] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Game].self, from: data)) ?? []
    }
}
