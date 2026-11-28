import Foundation

/// Built-in categories. Stores the raw value in `Game.categories` so that adding a new category in
/// a future release keeps previously persisted games readable.
public struct GameCategory: Identifiable, Hashable, Codable, Sendable {
    public let rawValue: String
    public let title: String
    public let symbolName: String

    public var id: String { rawValue }

    public init(rawValue: String, title: String, symbolName: String) {
        self.rawValue = rawValue
        self.title = title
        self.symbolName = symbolName
    }

    public init?(rawValue: String) {
        guard let match = Self.all.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = match
    }

    public static let all: [GameCategory] = [
        .init(rawValue: "acao", title: "Ação", symbolName: "flame.fill"),
        .init(rawValue: "rpg", title: "RPG", symbolName: "shield.lefthalf.filled"),
        .init(rawValue: "aventura", title: "Aventura", symbolName: "map.fill"),
        .init(rawValue: "esportes", title: "Esportes", symbolName: "sportscourt.fill"),
        .init(rawValue: "corrida", title: "Corrida", symbolName: "car.fill"),
        .init(rawValue: "terror", title: "Terror", symbolName: "moon.stars.fill"),
        .init(rawValue: "tiro", title: "Tiro", symbolName: "scope"),
        .init(rawValue: "luta", title: "Luta", symbolName: "figure.boxing"),
        .init(rawValue: "mundo-aberto", title: "Mundo Aberto", symbolName: "globe.americas.fill"),
        .init(rawValue: "soulslike", title: "Soulslike", symbolName: "skull.fill"),
        .init(rawValue: "estrategia", title: "Estratégia", symbolName: "chessboard.fill"),
        .init(rawValue: "familia", title: "Família", symbolName: "person.3.fill")
    ]

    public static var allRawValues: [String] { all.map(\.rawValue) }

    public static func title(for rawValue: String) -> String {
        GameCategory(rawValue: rawValue)?.title ?? rawValue.capitalized
    }
}
