import Foundation

/// Where a cover/banner image comes from.
///
/// The admin form accepts two kinds of values:
/// - a full `https://` URL (remote artwork), or
/// - the name of an image bundled with the app (used by the demo catalog, e.g. `cover_ghost`).
///
/// Anything else is rejected, so a typo never produces an invisible card.
public enum ArtworkReference: Equatable, Sendable {
    case remote(URL)
    case bundled(String)
    case none

    public init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self = .none
            return
        }
        if trimmed.contains("://") {
            self = HTTPSURLValidator.url(from: trimmed).map(ArtworkReference.remote) ?? .none
        } else {
            self = .bundled(trimmed)
        }
    }

    public var isValid: Bool {
        switch self {
        case .remote, .bundled: return true
        case .none: return false
        }
    }

    public var remoteURL: URL? {
        if case let .remote(url) = self { return url }
        return nil
    }

    public var bundledName: String? {
        if case let .bundled(name) = self { return name }
        return nil
    }
}
