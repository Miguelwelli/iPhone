import Foundation

/// Real UDP discovery over the Device Discovery Protocol (port 987).
///
/// Flow (identical to the official PlayStation app):
/// 1. Open a UDP socket and enable broadcast.
/// 2. Send `SRCH * HTTP/1.1` + `device-discovery-protocol-version:00020020` to 255.255.255.255:987.
/// 3. Parse every answer; consoles also answer unicast if re-sent after a first reply.
/// 4. Repeat every second until the timeout elapses.
///
/// Requires the "Local Network" permission on iOS (NSServiceBrowser) — see `Docs/PS4-SETUP.md`.
///
/// This class is deliberately *not* `Sendable`: it owns a socket and is meant to be driven from a
/// single actor/thread (`PS4DiscoveryService` on the app side).
public final class PS4Discovery {

    public enum DiscoveryError: LocalizedError, Equatable {
        case socketUnavailable(String)
        case noDevicesFound

        public var errorDescription: String? {
            switch self {
            case .socketUnavailable(let message):
                return "Não foi possível abrir a busca na rede local: \(message). Verifique a permissão de Rede Local do iOS."
            case .noDevicesFound:
                return "Nenhum console encontrado. Confirme que o PS4 está ligado e na mesma rede Wi-Fi."
            }
        }
    }

    public struct Options: Sendable {
        public var timeout: TimeInterval
        public var searchInterval: TimeInterval
        public var port: UInt16
        /// Extra interface broadcast addresses ("192.168.1.255") to try alongside 255.255.255.255.
        public var extraBroadcasts: [String]

        public init(timeout: TimeInterval = 8, searchInterval: TimeInterval = 0.8, port: UInt16 = 987, extraBroadcasts: [String] = []) {
            self.timeout = timeout
            self.searchInterval = searchInterval
            self.port = port
            self.extraBroadcasts = extraBroadcasts
        }
    }

    private var socketFD: Int32 = -1
    private var isCancelled = false

    public init() {}

    /// Starts a blocking scan. `onUpdate` is called on the calling thread for every new console
    /// (deduplicated by `host-id`). Returns all consoles found.
    @discardableResult
    public func scan(
        options: Options = Options(),
        onUpdate: ((PS4Device) -> Void)? = nil
    ) throws -> [PS4Device] {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        #endif
        guard fd >= 0 else {
            throw DiscoveryError.socketUnavailable(String(cString: strerror(errno)))
        }
        socketFD = fd
        defer { closeSocket() }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Do not block forever on recvfrom: 250 ms slices keep the loop responsive.
        #if canImport(Darwin)
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        #else
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        #endif
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var deviceMap: [String: PS4Device] = [:]
        var destinations = PS4DiscoveryProtocol.broadcastAddresses() + options.extraBroadcasts
        destinations.append("255.255.255.255")

        let packet = PS4DiscoveryProtocol.searchPacket()
        let deadline = Date().addingTimeInterval(options.timeout)
        var nextSearch = Date.distantPast
        var buffer = [UInt8](repeating: 0, count: 4096)

        while !isCancelled && Date() < deadline {
            if Date() >= nextSearch {
                for destination in Set(destinations) {
                    _ = sendPacket(packet, to: destination, port: options.port, fd: fd)
                }
                nextSearch = Date().addingTimeInterval(options.searchInterval)
            }

            var sender = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received: Int = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    recvfrom(fd, &buffer, buffer.count, 0, sockaddrPointer, &senderLength)
                }
            }
            guard received > 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addressCopy = sender.sin_addr
            inet_ntop(AF_INET, &addressCopy, &host, socklen_t(INET_ADDRSTRLEN))
            let address = String(cString: host)
            let data = Data(buffer[0..<received])
            guard let device = PS4DiscoveryProtocol.parseResponse(
                data,
                from: address,
                port: Int(UInt16(bigEndian: sender.sin_port))
            ) else { continue }
            if deviceMap[device.hostId] == nil {
                deviceMap[device.hostId] = device
                onUpdate?(device)
            } else if let existing = deviceMap[device.hostId], existing.address != device.address {
                deviceMap[device.hostId] = device
            }
        }
        return deviceMap.values.sorted { $0.displayName < $1.displayName }
    }

    public func cancel() {
        isCancelled = true
        closeSocket()
    }

    private func closeSocket() {
        if socketFD >= 0 {
            Foundation.close(socketFD)
            socketFD = -1
        }
    }

    private func sendPacket(_ data: Data, to host: String, port: UInt16, fd: Int32) -> Bool {
        var target = sockaddr_in()
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &target.sin_addr) == 1 else { return false }
        let sent: Int = withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                data.withUnsafeBytes { bytes in
                    Foundation.sendto(fd, bytes.baseAddress, data.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == data.count
    }
}
