import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Result of checking a .pkg link.
///
/// The rules are strict on purpose: a link is only `.verified` after the server actually answered and
/// the response looked like a binary package. Anything else is reported as unknown or rejected — the
/// app never claims a file is valid because the URL "looks right".
public enum PKGLinkStatus: Codable, Equatable, Sendable {
    case notProvided
    /// Link exists in the form but was never tested (offline, cancelled, or disabled in settings).
    case notChecked(String)
    case verified(byteCount: Int64?, contentType: String?)
    case rejected(String)

    public var isVerified: Bool {
        if case .verified = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .notProvided: return "Sem link PKG"
        case .notChecked: return "Link não testado"
        case .verified: return "Link PKG verificado"
        case .rejected: return "Link PKG inválido"
        }
    }

    public var detail: String {
        switch self {
        case .notProvided:
            return "Nenhum link informado. Você poderá adicioná-lo depois, após confirmar uma fonte autorizada."
        case .notChecked(let reason):
            return reason
        case .verified(let byteCount, let contentType):
            var parts: [String] = ["O servidor respondeu e entregou um arquivo binário."]
            if let byteCount, byteCount > 0 { parts.append("Tamanho: \(ByteFormatting.formatSize(byteCount)).") }
            if let contentType { parts.append("Tipo: \(contentType).") }
            return parts.joined(separator: " ")
        case .rejected(let reason):
            return reason
        }
    }
}

/// Performs a real HTTP check on a .pkg URL.
///
/// - HEAD first (cheap), falling back to a one-byte ranged GET for servers that do not implement HEAD.
/// - Rejects HTML pages, which are the usual sign of an expired or landing-page link.
/// - Never downloads the package itself.
public struct PKGLinkVerifier: Sendable {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func verify(_ raw: String) async -> PKGLinkStatus {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notProvided }
        guard HTTPSURLValidator.validate(trimmed, requiringPKG: true) == nil,
              let url = URL(string: trimmed) else {
            return .rejected("O link precisa ser HTTPS e terminar em .pkg.")
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 20
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            var (_, response) = try await session.data(for: request)
            var http = response as? HTTPURLResponse

            if let status = http?.statusCode, status == 405 || status == 501 {
                var ranged = URLRequest(url: url)
                ranged.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                ranged.timeoutInterval = 20
                (_, response) = try await session.data(for: ranged)
                http = response as? HTTPURLResponse
            }

            guard let http else { return .notChecked("Resposta inválida do servidor.") }
            switch http.statusCode {
            case 200, 206:
                break
            case 401, 403:
                return .rejected("O servidor exige autenticação (HTTP \(http.statusCode)); o link não é público.")
            case 404, 410:
                return .rejected("O arquivo não existe mais (HTTP \(http.statusCode)).")
            default:
                return .rejected("O servidor respondeu HTTP \(http.statusCode).")
            }

            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
                .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            let textTypes = ["text/html", "text/plain", "application/xhtml+xml", "application/json"]
            if textTypes.contains(contentType) {
                return .rejected("O endereço devolve uma página (\(contentType)), não um arquivo .pkg.")
            }

            let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
            if let length, length > 0, length < 256 * 1024 {
                return .rejected("O arquivo tem apenas \(ByteFormatting.formatSize(length)) — pequeno demais para um .pkg de PS4.")
            }
            return .verified(
                byteCount: http.expectedContentLength > 0 ? http.expectedContentLength : length,
                contentType: contentType.isEmpty ? nil : contentType
            )
        } catch {
            return .notChecked("Não foi possível testar o link agora: \(error.localizedDescription)")
        }
    }
}
