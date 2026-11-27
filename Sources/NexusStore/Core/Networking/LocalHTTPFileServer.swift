import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Tiny HTTP/1.1 file server that publishes the temporary `.pkg` on the local Wi-Fi so the PS4
/// browser can download it. Runs only while the transfer screen is open, serves a single file, and
/// requires a random 24-character token in the URL (the file is not browsable).
///
/// This is the honest fallback for consoles whose environment has a browser but no FTP server: the
/// user opens the shown LAN URL on the PS4 and downloads the package from the iPhone.
public final class LocalHTTPFileServer {

    public struct Info: Sendable {
        public var address: String
        public var port: UInt16
        public var path: String
        public var fileName: String
        public var fileSize: Int64

        public var url: String { "http://\(address):\(port)\(path)" }
    }

    public enum ServerError: LocalizedError, Equatable {
        case alreadyRunning
        case socket(String)
        case bind(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "O servidor HTTP local já está em execução."
            case .socket(let detail): return "Falha ao criar o servidor HTTP: \(detail)"
            case .bind(let detail): return "Falha ao abrir a porta local: \(detail)"
            }
        }
    }

    private let fileURL: URL
    private let token: String
    private let port: UInt16
    private let listenFD: Int32
    private let queue = DispatchQueue(label: "com.nexusstore.httpserver", qos: .utility)
    private var isRunning = true

    public private(set) var info: Info

    public init(fileURL: URL, preferredPort: UInt16 = 8080, token: String = LocalHTTPFileServer.randomToken()) throws {
        self.fileURL = fileURL
        self.token = token
        self.port = preferredPort

        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw ServerError.socket(String(cString: strerror(errno))) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = preferredPort.bigEndian
        address.sin_addr.s_addr = inet_addr("0.0.0.0")
        let bindResult: Int32 = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Foundation.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            let message = String(cString: strerror(errno))
            Foundation.close(fd)
            throw ServerError.bind(message)
        }
        guard Foundation.listen(fd, 8) == 0 else {
            let message = String(cString: strerror(errno))
            Foundation.close(fd)
            throw ServerError.bind(message)
        }
        // Discover the effective port (in case the OS assigned one).
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }
        let effectivePort = UInt16(bigEndian: bound.sin_port)
        listenFD = fd
        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.int64Value ?? 0
        info = Info(
            address: LocalHTTPFileServer.currentWiFiAddress() ?? "127.0.0.1",
            port: effectivePort,
            path: "/\(token)/\(fileURL.lastPathComponent)",
            fileName: fileURL.lastPathComponent,
            fileSize: size
        )
    }

    /// Starts accepting connections in the background.
    public func start() {
        let fd = listenFD
        queue.async { [weak self] in
            guard let self else { return }
            while self.isRunning {
                var clientAddress = sockaddr_in()
                var clientLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                let client: Int32 = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        accept(fd, sockaddrPointer, &clientLength)
                    }
                }
                if client < 0 {
                    if !self.isRunning { break }
                    continue
                }
                self.handle(client: client)
            }
        }
    }

    public func stop() {
        isRunning = false
        Foundation.close(listenFD)
    }

    public static func randomToken(length: Int = 24) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in characters.randomElement() ?? "a" })
    }

    // MARK: - Per-client handling

    private func handle(client: Int32) {
        defer { Foundation.close(client) }
        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        // Read until end of headers (bounded).
        while request.count < 8192 {
            let received = recv(client, &buffer, buffer.count, 0)
            if received <= 0 { return }
            request.append(buffer, count: received)
            if let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") { break }
        }
        guard let text = String(data: request, encoding: .utf8),
              let firstLine = text.split(separator: "\r\n").first else { return }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return }
        let method = String(parts[0])
        let target = String(parts[1])

        guard method == "GET" || method == "HEAD" else {
            writeResponse(client, status: "405 Method Not Allowed", body: "Método não suportado")
            return
        }
        guard target == info.path else {
            writeResponse(client, status: "404 Not Found", body: "Arquivo não encontrado")
            return
        }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            writeResponse(client, status: "500 Internal Server Error", body: "Arquivo indisponível")
            return
        }
        defer { try? handle.close() }

        var headers = "HTTP/1.1 200 OK\r\n"
        headers += "Content-Type: application/octet-stream\r\n"
        headers += "Content-Length: \(info.fileSize)\r\n"
        headers += "Content-Disposition: attachment; filename=\"\(info.fileName)\"\r\n"
        headers += "Connection: close\r\n\r\n"
        _ = sendAll(client, Data(headers.utf8))
        if method == "HEAD" { return }

        while true {
            guard let chunk = (try? handle.read(upToCount: 256 * 1024)) ?? nil, !chunk.isEmpty else { break }
            guard sendAll(client, chunk) else { return }
        }
    }

    private func writeResponse(_ client: Int32, status: String, body: String) {
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        _ = sendAll(client, Data(header.utf8))
        _ = sendAll(client, payload)
    }

    private func sendAll(_ client: Int32, _ data: Data) -> Bool {
        var sent = 0
        let flags = socketNoSignalFlag()
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return true }
            while sent < data.count {
                let result = send(client, base.advanced(by: sent), data.count - sent, flags)
                if result <= 0 { return false }
                sent += result
            }
            return true
        }
    }

    private func socketNoSignalFlag() -> Int32 {
        #if canImport(Glibc)
        return Int32(MSG_NOSIGNAL)
        #else
        return 0
        #endif
    }

    /// Best-effort local Wi-Fi IPv4 (en0 on iOS). Returns nil when only cellular is available.
    public static func currentWiFiAddress() -> String? {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            let interface = entry.pointee
            if interface.ifa_addr?.pointee.sa_family == sa_family_t(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" || name.hasPrefix("eth") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    var addrCopy = interface.ifa_addr.pointee
                    let addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                    if getnameinfo(&addrCopy, addressLength,
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let value = String(cString: host)
                        if !value.isEmpty && !value.hasPrefix("169.254") { addresses.append(value) }
                    }
                }
            }
            pointer = interface.ifa_next
        }
        return addresses.first
    }
}
