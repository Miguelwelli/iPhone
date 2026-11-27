import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Errors surfaced by the FTP client / transfer engine. Messages are user facing (pt-BR) because the
/// app presents them directly in the transfer screen and the connection screen.
public enum FTPError: LocalizedError, Equatable, Sendable {
    case notConnected
    case socket(String)
    case timeout(String)
    case closedByServer
    case unexpectedReply(command: String, reply: String)
    case loginFailed(String)
    case tlsRequired
    case passiveModeFailed(String)
    case dataConnectionFailed(String)
    case cancelled
    case localFile(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Sem conexão com o servidor FTP."
        case .socket(let detail):
            return "Falha de rede: \(detail)"
        case .timeout(let detail):
            return "Tempo esgotado: \(detail)"
        case .closedByServer:
            return "O servidor encerrou a conexão."
        case let .unexpectedReply(command, reply):
            return "Resposta inesperada do servidor para \(command): \(reply)"
        case .loginFailed(let reply):
            return "Login recusado pelo servidor: \(reply)"
        case .tlsRequired:
            return "O servidor exige FTPS (TLS), que ainda não é suportado. Use o servidor FTP padrão do console."
        case .passiveModeFailed(let reply):
            return "Não foi possível abrir o modo passivo (PASV): \(reply)"
        case .dataConnectionFailed(let detail):
            return "Não foi possível abrir a conexão de dados: \(detail)"
        case .cancelled:
            return "Transferência cancelada."
        case .localFile(let detail):
            return "Falha no arquivo local: \(detail)"
        case .unsupported(let detail):
            return "Operação não suportada: \(detail)"
        }
    }
}

/// A single FTP reply (`code` + full text, including multi-line replies kept together).
public struct FTPReply: Equatable, Sendable {
    public var code: Int
    public var lines: [String]

    public init(code: Int, lines: [String]) {
        self.code = code
        self.lines = lines
    }

    public var message: String {
        lines.map { line -> String in
            // Strip the "123-" / "123 " prefixes for display.
            if line.count > 4, let firstSpace = line.firstIndex(where: { $0 == " " || $0 == "-" }) {
                return String(line[line.index(after: firstSpace)...])
            }
            return line
        }.joined(separator: " ")
    }

    public var isPositiveCompletion: Bool { (200..<300).contains(code) }
    public var isPositiveIntermediate: Bool { (300..<400).contains(code) }
    public var rawSummary: String { "[\(code)] \(message)" }
}

/// A byte-level, blocking TCP connection. Abstracted so the FTP dialogue can be unit-tested with a
/// scripted socket, and so the same client works on Darwin and Linux.
public protocol FTPSocket: AnyObject {
    func connect(host: String, port: UInt16, timeout: TimeInterval) throws
    /// Returns the bytes read (may be fewer than requested). `nil` means the peer closed.
    func read(maxLength: Int) throws -> Data?
    func write(_ data: Data) throws
    func close()
}

/// Creates sockets. Injectable for tests.
public protocol FTPSocketProvider: Sendable {
    func makeSocket() -> FTPSocket
}

/// Real BSD socket provider (works on iOS and Linux).
public struct BSDFTPSocketProvider: FTPSocketProvider {
    public init() {}
    public func makeSocket() -> FTPSocket { BSDFTPSocket() }
}

/// POSIX TCP socket with timeouts. Used for both the FTP control channel and each data connection
/// (the app always negotiates passive mode, which is the only mode that works behind NAT).
public final class BSDFTPSocket: FTPSocket {

    private var descriptor: Int32 = -1
    private let readTimeout: TimeInterval

    public init(readTimeout: TimeInterval = 30) {
        self.readTimeout = readTimeout
    }

    deinit { close() }

    public func connect(host: String, port: UInt16, timeout: TimeInterval) throws {
        close()
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = Self.streamSocketType
        hints.ai_protocol = Self.tcpProtocol

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let list = result else {
            throw FTPError.socket("não foi possível resolver “\(host)” (código \(status))")
        }
        defer { freeaddrinfo(list) }

        var lastError = "endereço indisponível"
        var pointer: UnsafeMutablePointer<addrinfo>? = list
        while let info = pointer {
            let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if fd >= 0 {
                var on: Int32 = 1
                setsockopt(fd, SOL_SOCKET, socketIntOptionNoSigPipe, &on, socklen_t(MemoryLayout<Int32>.size))
                var tv = timeval(tv_sec: Int(readTimeout), tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                if Foundation.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                    descriptor = fd
                    return
                }
                lastError = String(cString: strerror(errno))
                Foundation.close(fd)
            } else {
                lastError = String(cString: strerror(errno))
            }
            pointer = info.pointee.ai_next
        }
        throw FTPError.socket("conexão a \(host):\(port) falhou (\(lastError))")
    }

    public func read(maxLength: Int) throws -> Data? {
        guard descriptor >= 0 else { throw FTPError.notConnected }
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let received: Int = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return recv(descriptor, base, maxLength, 0)
        }
        if received > 0 {
            return Data(buffer[0..<received])
        }
        if received == 0 { return nil }
        if errno == EAGAIN || errno == EWOULDBLOCK {
            throw FTPError.timeout("nenhum dado recebido do servidor")
        }
        throw FTPError.socket(String(cString: strerror(errno)))
    }

    public func write(_ data: Data) throws {
        guard descriptor >= 0 else { throw FTPError.notConnected }
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let result = send(descriptor, base.advanced(by: sent), data.count - sent, socketSendFlags)
                if result > 0 {
                    sent += result
                } else if result < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    throw FTPError.timeout("envio bloqueado")
                } else {
                    throw FTPError.socket(String(cString: strerror(errno)))
                }
            }
        }
    }

    public func close() {
        if descriptor >= 0 {
            Foundation.close(descriptor)
            descriptor = -1
        }
    }

    // MARK: - Platform details

    private static var streamSocketType: Int32 {
        #if canImport(Glibc)
        return Int32(SOCK_STREAM.rawValue)
        #else
        return SOCK_STREAM
        #endif
    }

    private static var tcpProtocol: Int32 {
        #if canImport(Glibc)
        return Int32(IPPROTO_TCP)
        #else
        return IPPROTO_TCP
        #endif
    }

    /// Prevents SIGPIPE from killing the process when a peer disappears mid-transfer.
    private var socketIntOptionNoSigPipe: Int32 {
        #if canImport(Darwin)
        return SO_NOSIGPIPE
        #else
        return 0
        #endif
    }

    private var socketSendFlags: Int32 {
        #if canImport(Glibc)
        return Int32(MSG_NOSIGNAL)
        #else
        return 0
        #endif
    }
}
