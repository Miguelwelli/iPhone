import Foundation
import SwiftUI

/// Preferences that must survive an app relaunch but do not belong to the game catalog.
@MainActor
public final class SettingsStore: ObservableObject {

    public struct Value: Codable, Equatable {
        public var favoriteCategories: [String]
        public var recentSearches: [String]
        public var homeCategory: String?

        public init(favoriteCategories: [String] = [], recentSearches: [String] = [], homeCategory: String? = nil) {
            self.favoriteCategories = favoriteCategories
            self.recentSearches = recentSearches
            self.homeCategory = homeCategory
        }
    }

    @Published private(set) public var value: Value
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Value.self, from: data) {
            value = decoded
        } else {
            value = Value()
        }
    }

    public func toggleCategory(_ rawValue: String) {
        update { value in
            if let index = value.favoriteCategories.firstIndex(of: rawValue) {
                value.favoriteCategories.remove(at: index)
            } else {
                value.favoriteCategories.append(rawValue)
            }
        }
    }

    public func isFavoriteCategory(_ rawValue: String) -> Bool {
        value.favoriteCategories.contains(rawValue)
    }

    public func recordSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        update { value in
            value.recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
            value.recentSearches.insert(trimmed, at: 0)
            if value.recentSearches.count > 8 {
                value.recentSearches = Array(value.recentSearches.prefix(8))
            }
        }
    }

    public func clearSearches() {
        update { $0.recentSearches.removeAll() }
    }

    public func setHomeCategory(_ rawValue: String?) {
        update { $0.homeCategory = rawValue }
    }

    private func update(_ mutate: (inout Value) -> Void) {
        var next = value
        mutate(&next)
        value = next
        if let data = try? JSONEncoder().encode(next) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
