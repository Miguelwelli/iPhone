import Foundation

/// The real option matrix for moving a `.pkg` from the iPhone to a PS4.
///
/// The app is explicit with the user about what is and is not possible, instead of pretending that
/// "download + FTP = installed game":
///
/// | Route | Availability |
/// |---|---|
/// | `ftp` | Any PS4 running a **user-supplied** FTP server (e.g. a homebrew package server) on the local network. The app uploads the `.pkg` over plain FTP, passive mode, port 2121 by default. It does **not** install anything. |
/// | `ps4web` | The console's built-in web server (`install via web`, used by the PS4 exploit toolkit / "package installer" pages) accepts an HTTP POST of the package to port 12800. Implemented in `PS4InstallerClient`. |
/// | `httpServer` | The iPhone serves the temporary `.pkg` over HTTP; the PS4 browser downloads it from the LAN URL. Implemented in `LocalHTTPFileServer`. |
public enum SendingMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case ftp
    case ps4web
    case httpServer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ftp: return "FTP (servidor do console)"
        case .ps4web: return "Instalador do console (porta 12800)"
        case .httpServer: return "iPhone como servidor HTTP para o navegador do PS4"
        }
    }

    public var shortTitle: String {
        switch self {
        case .ftp: return "FTP"
        case .ps4web: return "Instalador"
        case .httpServer: return "HTTP local"
        }
    }

    public var detail: String {
        switch self {
        case .ftp:
            return "Envia o arquivo por FTP para o console que estiver executando um servidor FTP compatível. O envio não instala o jogo automaticamente."
        case .ps4web:
            return "O console precisa aceitar pacotes no instalador local (porta 12800) e o seu ambiente deve permitir esse recurso. O app não contorna bloqueios."
        case .httpServer:
            return "O iPhone publica o arquivo na rede Wi-Fi; você abre o endereço no navegador do PS4 para baixar o pacote. Não instala automaticamente."
        }
    }

    public var isAutomatic: Bool {
        switch self {
        case .ftp, .ps4web: return true
        case .httpServer: return false
        }
    }
}

/// Errors surfaced while sending a package.
public enum SendError: LocalizedError, Equatable {
    case invalidURL(String)
    case insufficientStorage(required: Int64, available: Int64)
    case downloadFailed(String)
    case uploadFailed(String)
    case installerRejected(status: Int, body: String)
    case httpServerFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let detail):
            return "Link inválido: \(detail)"
        case let .insufficientStorage(required, available):
            return "Espaço insuficiente no iPhone. Necessário \(ByteFormatting.formatSize(required)), disponível \(ByteFormatting.formatSize(available))."
        case .downloadFailed(let detail):
            return "Falha no download: \(detail)"
        case .uploadFailed(let detail):
            return "Falha no envio ao console: \(detail)"
        case let .installerRejected(status, body):
            return "O console recusou o pacote (HTTP \(status)). \(body.isEmpty ? "" : "Resposta: \(body.prefix(160))")"
        case .httpServerFailed(let detail):
            return "Servidor HTTP local: \(detail)"
        case .cancelled:
            return "Operação cancelada."
        }
    }
}
