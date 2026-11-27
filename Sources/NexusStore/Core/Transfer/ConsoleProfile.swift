import Foundation

/// A console the app can send files to. Discovered consoles are stored here too (with `isManual`
/// false) so that reconnecting later does not require a new network scan.
public struct ConsoleProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    public var username: String
    public var remotePath: String
    public var isManual: Bool
    public var lastConnectedAt: Date?
    public var notes: String
    /// Preferred way of sending files to this console (see `SendingMethod`).
    public var preferredMethod: SendingMethod

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 2121,
        username: String = "anonymous",
        remotePath: String = "/",
        isManual: Bool = false,
        lastConnectedAt: Date? = nil,
        notes: String = "",
        preferredMethod: SendingMethod = .ftp
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.remotePath = remotePath
        self.isManual = isManual
        self.lastConnectedAt = lastConnectedAt
        self.notes = notes
        self.preferredMethod = preferredMethod
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(UInt16.self, forKey: .port)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? "anonymous"
        remotePath = try container.decodeIfPresent(String.self, forKey: .remotePath) ?? "/"
        isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? true
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        preferredMethod = try container.decodeIfPresent(SendingMethod.self, forKey: .preferredMethod) ?? .ftp
    }

    /// Validates host/port/paths before a connection attempt. Returns a user-facing message.
    public func validationError() -> String? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.isEmpty { return "Informe o endereço IP do console." }
        let hostPattern = #"^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[A-Za-z0-9\-\.]+$"#
        if trimmedHost.range(of: hostPattern, options: .regularExpression) == nil {
            return "Endereço IP inválido."
        }
        if host.contains(" ") { return "O endereço não pode conter espaços." }
        if port == 0 { return "Informe a porta FTP (normalmente 2121)." }
        if remotePath.contains(" ") || remotePath.isEmpty { return "Informe um caminho remoto válido (ex.: /)." }
        return nil
    }

    public var displayAddress: String { "\(host):\(port)" }
}

/// Settings applied to every transfer.
public struct TransferConfiguration: Codable, Equatable, Sendable {
    /// When true the temporary .pkg is deleted from the iPhone after a successful upload.
    public var deleteLocalFileWhenDone: Bool
    /// Deletes partial downloads when a job is cancelled or removed.
    public var cleanTemporaryFilesOnCancel: Bool
    /// Requires the remote file to reach the expected size when the server reports `SIZE`.
    public var verifyRemoteSizeWhenAvailable: Bool

    public init(
        deleteLocalFileWhenDone: Bool = true,
        cleanTemporaryFilesOnCancel: Bool = true,
        verifyRemoteSizeWhenAvailable: Bool = true
    ) {
        self.deleteLocalFileWhenDone = deleteLocalFileWhenDone
        self.cleanTemporaryFilesOnCancel = cleanTemporaryFilesOnCancel
        self.verifyRemoteSizeWhenAvailable = verifyRemoteSizeWhenAvailable
    }
}
