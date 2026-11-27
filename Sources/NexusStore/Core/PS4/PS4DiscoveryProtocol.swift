import Foundation

/// A console answer to a DDP discovery broadcast.
public struct PS4Device: Identifiable, Hashable, Sendable {
    public var hostId: String
    public var hostName: String
    public var hostType: String
    public var address: String
    public var ddpPort: Int
    public var requestPort: Int?
    /// `true` when the answer status line was "200 Ok", `false` for "620 Server Standby".
    public var isAwake: Bool
    public var statusLine: String
    public var rawFields: [String: String]
    public var discoveredAt: Date

    public var id: String { hostId }

    public init(
        hostId: String,
        hostName: String,
        hostType: String,
        address: String,
        ddpPort: Int,
        requestPort: Int? = nil,
        isAwake: Bool,
        statusLine: String,
        rawFields: [String: String] = [:],
        discoveredAt: Date = Date()
    ) {
        self.hostId = hostId
        self.hostName = hostName
        self.hostType = hostType
        self.address = address
        self.ddpPort = ddpPort
        self.requestPort = requestPort
        self.isAwake = isAwake
        self.statusLine = statusLine
        self.rawFields = rawFields
        self.discoveredAt = discoveredAt
    }

    public var displayName: String {
        hostName.isEmpty ? "PS4 (\(address))" : hostName
    }

    public var typeDescription: String {
        switch hostType.uppercased() {
        case "PS4": return "PlayStation 4"
        case "PS5": return "PlayStation 5"
        default: return hostType.isEmpty ? "Console PlayStation" : hostType
        }
    }
}

/// Implements the *Device Discovery Protocol* (DDP) used by the PlayStation app / Remote Play.
///
/// This is the real protocol used to find a PS4 on the local network (UDP port 987): the phone
/// broadcasts a `SRCH * HTTP/1.1` packet with the `device-discovery-protocol-version` header and
/// every console answers with an HTTP-like packet containing `host-id`, `host-name`, `host-type`,
/// `host-request-port` and a status line (`200 Ok` when awake, `620 Server Standby` when in rest
/// mode). See `Docs/ARCHITECTURE.md` for the protocol source references.
///
/// Careful: DDP only *discovers* a console. It does not open files, and it does not mean an FTP
/// server is running on the console (that depends on a separate homebrew/community service).
public enum PS4DiscoveryProtocol {

    public static let discoveryPort = 987
    public static let protocolVersion = "00020020"

    /// Builds the discovery request sent to `255.255.255.255:987`.
    public static func searchPacket(version: String = protocolVersion) -> Data {
        let text = "SRCH * HTTP/1.1\ndevice-discovery-protocol-version:\(version)\n"
        return Data(text.utf8)
    }

    /// Parses a DDP answer. Returns nil for packets that are not console announcements.
    public static func parseResponse(_ data: Data, from address: String, port: Int) -> PS4Device? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard let statusLine = lines.first, statusLine.uppercased().hasPrefix("HTTP") else { return nil }

        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { fields[key] = value }
        }

        guard let hostId = fields["host-id"] ?? fields["hostid"] ?? fields["host_id"], !hostId.isEmpty else {
            return nil
        }
        let code = statusLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let requestPort = fields["host-request-port"].flatMap(Int.init)
        return PS4Device(
            hostId: hostId,
            hostName: fields["host-name"] ?? "",
            hostType: fields["host-type"] ?? "",
            address: address,
            ddpPort: port,
            requestPort: requestPort,
            isAwake: code == "200",
            statusLine: statusLine,
            rawFields: fields
        )
    }

    /// Broadcast destinations to try, in order.
    public static func broadcastAddresses() -> [String] {
        ["255.255.255.255"]
    }
}
