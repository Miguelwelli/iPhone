import Foundation

/// Minimal but real FTP client (RFC 959) used to send `.pkg` files to a console that is running a
/// compatible FTP server.
///
/// Scope and honesty notes:
/// - Commands implemented: `USER`, `PASS`, `SYST`, `TYPE`, `PWD`, `CWD`, `MKD`, `PASV`/`EPSV`,
///   `STOR` (upload), `SIZE`, `LIST`/`MLSD` (listing) and `QUIT`.
/// - **Passive mode only.** Active mode cannot work behind the NAT of a home network / iOS.
/// - Plain FTP only. If the server requires AUTH TLS (i.e. "530 Please login with USER and PASS"
///   style replies or an explicit `AUTH TLS` requirement), `FTPError.tlsRequired` is thrown —
///   FTPS is *not* silently pretended to work.
/// - Everything is synchronous and blocking; the transfer engine calls it from a dedicated queue.
public final class FTPClient {

    private let provider: FTPSocketProvider
    private var control: FTPSocket?
    private var pending = Data()
    private(set) var isConnected = false

    public private(set) var host: String = ""
    public private(set) var port: UInt16 = 0
    /// Read/write timeout in seconds for both control and data channels.
    public var timeout: TimeInterval = 30
    /// Maximum bytes per FTP command line read; guards against a misbehaving server.
    private let maxLineLength = 16 * 1024

    public init(provider: FTPSocketProvider = BSDFTPSocketProvider()) {
        self.provider = provider
    }

    deinit { quitSilently() }

    // MARK: - Connection

    /// Opens the control channel and waits for the 220 greeting.
    public func connect(host: String, port: UInt16 = 2121, timeout: TimeInterval = 20) throws {
        self.host = host
        self.port = port
        self.timeout = timeout
        let socket = provider.makeSocket()
        do {
            try socket.connect(host: host, port: port, timeout: timeout)
        } catch {
            socket.close()
            throw FTPError.socket("não foi possível alcançar \(host):\(port). Verifique o Wi-Fi e o servidor FTP do console. (\(error.localizedDescription))")
        }
        control = socket
        pending.removeAll()
        isConnected = true
        do {
            let reply = try readReply()
            guard reply.code == 220 || reply.code == 120 else {
                quitSilently()
                throw FTPError.unexpectedReply(command: "conexão", reply: reply.rawSummary)
            }
        } catch {
            quitSilently()
            throw error
        }
    }

    /// Authenticates. A 230 reply means the user is already logged in; 331 asks for a password.
    public func login(user: String, password: String) throws {
        let userReply = try send("USER \(user)")
        switch userReply.code {
        case 230:
            return
        case 331:
            let passReply = try send("PASS \(password)")
            guard passReply.code == 230 || passReply.code == 202 else {
                throw FTPError.loginFailed(passReply.rawSummary)
            }
        case 332:
            throw FTPError.tlsRequired
        default:
            throw FTPError.loginFailed(userReply.rawSummary)
        }
    }

    /// Convenience: connect + login + binary mode in one call.
    public func connectAndLogin(host: String, port: UInt16, user: String, password: String, timeout: TimeInterval = 20) throws {
        try connect(host: host, port: port, timeout: timeout)
        try login(user: user, password: password)
        _ = try? systemType()
        _ = try? enterBinaryMode()
    }

    public func quitSilently() {
        guard isConnected, let control else { return }
        isConnected = false
        _ = try? write("QUIT\r\n", to: control)
        // Give the server a moment to reply, then close regardless.
        _ = try? readReply()
        control.close()
        self.control = nil
        pending.removeAll()
    }

    // MARK: - Commands

    public func send(_ command: String) throws -> FTPReply {
        guard let control, isConnected else { throw FTPError.notConnected }
        try write(command + "\r\n", to: control)
        return try readReply()
    }

    public func systemType() throws -> String {
        let reply = try send("SYST")
        guard reply.isPositiveCompletion else {
            throw FTPError.unexpectedReply(command: "SYST", reply: reply.rawSummary)
        }
        return reply.message
    }

    @discardableResult
    public func enterBinaryMode() throws -> FTPReply {
        let reply = try send("TYPE I")
        guard reply.isPositiveCompletion else {
            throw FTPError.unexpectedReply(command: "TYPE I", reply: reply.rawSummary)
        }
        return reply
    }

    public func currentDirectory() throws -> String {
        let reply = try send("PWD")
        guard reply.isPositiveCompletion else {
            throw FTPError.unexpectedReply(command: "PWD", reply: reply.rawSummary)
        }
        // 257 "/" is current directory
        if let first = reply.message.firstIndex(of: "\""),
           let last = reply.message.lastIndex(of: "\""), first < last {
            return String(reply.message[reply.message.index(after: first)..<last])
        }
        return reply.message
    }

    @discardableResult
    public func changeDirectory(_ path: String) throws -> FTPReply {
        let reply = try send("CWD \(path)")
        guard reply.isPositiveCompletion else {
            throw FTPError.unexpectedReply(command: "CWD \(path)", reply: reply.rawSummary)
        }
        return reply
    }

    /// Creates a directory; returns nil when it already exists (550) instead of throwing.
    @discardableResult
    public func makeDirectoryIfNeeded(_ path: String) throws -> FTPReply? {
        let reply = try send("MKD \(path)")
        if reply.code == 550 || reply.code == 521 { return nil }
        guard reply.isPositiveCompletion || reply.code == 257 else {
            throw FTPError.unexpectedReply(command: "MKD \(path)", reply: reply.rawSummary)
        }
        return reply
    }

    /// Remote file size in bytes, when the server implements `SIZE` (many do not).
    public func remoteFileSize(_ name: String) -> Int64? {
        guard let reply = try? send("SIZE \(name)"), reply.isPositiveCompletion else { return nil }
        return Int64(reply.message.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Passive mode

    /// Negotiates a passive data endpoint. Prefers PASV, falls back to EPSV.
    public func passiveEndpoint() throws -> (host: String, port: UInt16) {
        if let endpoint = try? pasvEndpoint() { return endpoint }
        return try epsvEndpoint()
    }

    private func pasvEndpoint() throws -> (host: String, port: UInt16) {
        let reply = try send("PASV")
        guard reply.code == 227 else {
            throw FTPError.passiveModeFailed(reply.rawSummary)
        }
        // 227 Entering Passive Mode (192,168,1,104,196,52).
        guard let open = reply.message.firstIndex(of: "("),
              let close = reply.message.lastIndex(of: ")"), open < close else {
            throw FTPError.passiveModeFailed(reply.rawSummary)
        }
        let numbers = reply.message[reply.message.index(after: open)..<close]
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 6 else {
            throw FTPError.passiveModeFailed(reply.rawSummary)
        }
        let returnedHost = numbers[0...3].map(String.init).joined(separator: ".")
        let dataPort = numbers[4] * 256 + numbers[5]
        guard dataPort > 0, dataPort <= 65535 else {
            throw FTPError.passiveModeFailed(reply.rawSummary)
        }
        // Some servers behind NAT advertise an unroutable address; in that case reuse the control
        // host, which is what every mainstream FTP client does.
        let candidate = (numbers[0] == 0 && numbers[1] == 0 && numbers[2] == 0 && numbers[3] == 0)
            ? host : returnedHost
        return (candidate, UInt16(dataPort))
    }

    private func epsvEndpoint() throws -> (host: String, port: UInt16) {
        let reply = try send("EPSV")
        guard reply.code == 229 else {
            throw FTPError.passiveModeFailed(reply.rawSummary)
        }
        // 229 Entering Extended Passive Mode (|||24812|)
        guard let open = reply.message.firstIndex(of: "("),
              let close = reply.message.lastIndex(of: ")"), open < close else {
            throw FTPError.passiveModeFailed(reply.rawSummary)
        }
        let inner = reply.message[reply.message.index(after: open)..<close]
        let digits = inner.filter(\.isNumber)
        guard let dataPort = Int(digits), dataPort > 0, dataPort <= 65535 else {
            throw FTPError.passiveModeFailed(reply.rawSummary)
        }
        return (host, UInt16(dataPort))
    }

    // MARK: - Upload

    /// Uploads a local file with `STOR`, streaming it in 64 KiB chunks.
    ///
    /// - Parameters:
    ///   - progress: called after each chunk with (bytesSent, totalBytes). Invoked on the calling thread.
    ///   - isCancelled: polled before each chunk; when true the data connection is aborted and
    ///     `FTPError.cancelled` is thrown.
    /// - Returns: number of bytes sent.
    @discardableResult
    public func upload(
        fileURL: URL,
        remoteName: String,
        progress: ((Int64, Int64) -> Void)? = nil,
        isCancelled: (() -> Bool)? = nil
    ) throws -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let total = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw FTPError.localFile("não foi possível abrir \(fileURL.lastPathComponent)")
        }
        defer { try? handle.close() }

        let endpoint = try passiveEndpoint()
        let dataSocket = provider.makeSocket()
        do {
            try dataSocket.connect(host: endpoint.host, port: endpoint.port, timeout: timeout)
        } catch {
            dataSocket.close()
            throw FTPError.dataConnectionFailed(error.localizedDescription)
        }

        let storReply: FTPReply
        do {
            storReply = try send("STOR \(remoteName)")
        } catch {
            dataSocket.close()
            throw error
        }
        guard storReply.code == 150 || storReply.code == 125 || storReply.isPositiveCompletion else {
            dataSocket.close()
            throw FTPError.unexpectedReply(command: "STOR", reply: storReply.rawSummary)
        }

        var sent: Int64 = 0
        let chunkSize = 64 * 1024
        do {
            while true {
                if isCancelled?() == true {
                    dataSocket.close()
                    _ = try? send("ABOR")
                    throw FTPError.cancelled
                }
                let chunk = try handle.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { break }
                try dataSocket.write(chunk)
                sent += Int64(chunk.count)
                progress?(sent, total)
            }
        } catch {
            dataSocket.close()
            if error is FTPError { throw error }
            throw FTPError.dataConnectionFailed(error.localizedDescription)
        }
        dataSocket.close()

        let completion = try readReply()
        // Expect 226 "Closing data connection"; some servers send 250.
        guard completion.code == 226 || completion.code == 250 || completion.isPositiveCompletion else {
            throw FTPError.unexpectedReply(command: "STOR (conclusão)", reply: completion.rawSummary)
        }
        return sent
    }

    // MARK: - Listing

    public struct RemoteEntry: Equatable, Sendable {
        public var name: String
        public var isDirectory: Bool
        public var size: Int64?

        public init(name: String, isDirectory: Bool, size: Int64? = nil) {
            self.name = name
            self.isDirectory = isDirectory
            self.size = size
        }
    }

    /// Lists the current directory using MLSD when supported, otherwise LIST.
    public func listDirectory() throws -> [RemoteEntry] {
        let endpoint = try passiveEndpoint()
        let dataSocket = provider.makeSocket()
        do {
            try dataSocket.connect(host: endpoint.host, port: endpoint.port, timeout: timeout)
        } catch {
            dataSocket.close()
            throw FTPError.dataConnectionFailed(error.localizedDescription)
        }
        defer { dataSocket.close() }

        let mlsd = try send("MLSD")
        let useMLSD = mlsd.code == 150 || mlsd.code == 125
        if !useMLSD {
            let list = try send("LIST")
            guard list.code == 150 || list.code == 125 || list.isPositiveCompletion else {
                throw FTPError.unexpectedReply(command: "LIST", reply: list.rawSummary)
            }
        }

        var payload = Data()
        while let chunk = try dataSocket.read(maxLength: 64 * 1024) {
            payload.append(chunk)
        }
        _ = try? readReply()

        let text = String(data: payload, encoding: .utf8) ?? ""
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if useMLSD {
            return lines.compactMap { line -> RemoteEntry? in
                // type=file;size=1234; name
                guard let spaceIndex = line.firstIndex(of: " ") else { return nil }
                let facts = line[..<spaceIndex].split(separator: ";")
                let name = String(line[line.index(after: spaceIndex)...])
                var isDirectory = false
                var size: Int64?
                for fact in facts {
                    let parts = fact.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    switch parts[0].lowercased() {
                    case "type": isDirectory = parts[1].lowercased() == "dir"
                    case "size": size = Int64(parts[1])
                    default: break
                    }
                }
                return RemoteEntry(name: name, isDirectory: isDirectory, size: size)
            }
        }
        return lines.compactMap { Self.parseListLine($0) }
    }

    /// Parses a `LIST` line: `-rw-r--r-- 1 root root 1234 Jan 01 12:00 name.pkg`
    static func parseListLine(_ line: String) -> RemoteEntry? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 9 else { return nil }
        let permissions = String(parts[0])
        guard permissions.count >= 10 else { return nil }
        let isDirectory = permissions.hasPrefix("d")
        let size = Int64(parts[4])
        let name = parts[8...].joined(separator: " ")
        return RemoteEntry(name: name, isDirectory: isDirectory, size: size)
    }

    // MARK: - Low level I/O

    private func write(_ text: String, to socket: FTPSocket) throws {
        guard let data = text.data(using: .utf8) else { throw FTPError.socket("codificação inválida") }
        try socket.write(data)
    }

    /// Reads one complete FTP reply, joining multi-line replies ("123-..." until "123 ").
    public func readReply() throws -> FTPReply {
        guard control != nil else { throw FTPError.notConnected }
        var lines: [String] = []
        var code = 0
        while true {
            let line = try readLine()
            lines.append(line)
            if let leading = Self.leadingCode(line) {
                if lines.count == 1 {
                    code = leading
                    // Single-line reply: "220 Hello" (4th char is a space or the line is just the code)
                    if line.count == 3 || line.dropFirst(3).first == " " {
                        break
                    }
                } else if leading == code, line.count >= 4, line.dropFirst(3).first == " " {
                    break
                }
            }
            if lines.count > 200 {
                throw FTPError.unexpectedReply(command: "resposta", reply: "resposta longa demais")
            }
        }
        return FTPReply(code: code, lines: lines)
    }

    private func readLine() throws -> String {
        while true {
            if let newline = pending.firstIndex(of: 0x0A) {
                var lineBytes = pending[pending.startIndex..<newline]
                if lineBytes.last == 0x0D { lineBytes = lineBytes.dropLast() }
                let line = String(decoding: lineBytes, as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                return line
            }
            guard pending.count < maxLineLength else {
                pending.removeAll()
                throw FTPError.unexpectedReply(command: "resposta", reply: "linha longa demais")
            }
            guard let control else { throw FTPError.notConnected }
            guard let chunk = try control.read(maxLength: 4096) else {
                throw FTPError.closedByServer
            }
            pending.append(chunk)
        }
    }

    static func leadingCode(_ line: String) -> Int? {
        guard line.count >= 3 else { return nil }
        let prefix = line.prefix(3)
        guard prefix.allSatisfy(\.isNumber) else { return nil }
        return Int(prefix)
    }
}
