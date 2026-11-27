import Foundation

/// Validation errors for URLs typed by the user.
public enum URLValidationError: Error, Equatable, Sendable {
    case empty
    case malformed
    case insecureScheme
    case missingHost
    case notPKG

    public var message: String {
        switch self {
        case .empty:
            return "O link está vazio."
        case .malformed:
            return "Link inválido. Verifique o endereço digitado."
        case .insecureScheme:
            return "Use HTTPS. O iOS bloqueia conexões HTTP abertas por padrão (ATS)."
        case .missingHost:
            return "O link não possui um servidor válido."
        case .notPKG:
            return "O link deve apontar para um arquivo .pkg."
        }
    }
}

/// Central URL validation. Keeping it in one place means the admin form, the transfer engine and the
/// PS4 connection screen all apply the same App Transport Security compatible rules.
public enum HTTPSURLValidator {

    /// Validates a download link. `requiringPKG` enforces the `.pkg` path extension.
    public static func validate(_ raw: String, requiringPKG: Bool) -> URLValidationError? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return .malformed }
        guard scheme == "https" else { return .insecureScheme }
        guard let host = url.host, !host.isEmpty else { return .missingHost }
        if requiringPKG {
            let path = url.path.lowercased()
            guard path.hasSuffix(".pkg") else { return .notPKG }
        }
        return nil
    }

    /// Returns the URL when it is a valid, ATS-compatible https URL; nil otherwise.
    public static func url(from raw: String) -> URL? {
        guard validate(raw, requiringPKG: false) == nil else { return nil }
        return URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Suggests a file name from a URL path, falling back to the provided default.
    public static func suggestedFileName(for url: URL, fallback: String) -> String {
        let last = url.lastPathComponent
        return last.isEmpty || last == "/" ? fallback : last
    }
}

/// Text folding used by the search feature.
public enum SearchText {
    public static func fold(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
