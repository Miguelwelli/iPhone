import Foundation
import SwiftUI

/// Drives console discovery and connection from the UI.
///
/// Everything reported here comes from real network operations:
/// - `scan()` broadcasts DDP packets on the local network (UDP 987) and lists the consoles that
///   actually answered. A device shown as "Disponível" answered the broadcast; nothing is invented.
/// - `connect()` performs a real FTP login against the console address to prove that a compatible
///   FTP server is running and reachable.
/// - If no console is found (Wi-Fi restrictions, console in standby, no FTP server), the screen shows
///   exactly that and offers manual configuration.
@MainActor
public final class PS4ConnectionService: ObservableObject {

    public enum Status: Equatable {
        case idle
        case searching
        case searchingFinished(Int)
        case connecting(String)
        case connected
        case failed(String)
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var discovered: [PS4Device] = []
    @Published public private(set) var connectedProfile: ConsoleProfile?
    @Published public private(set) var lastScanDate: Date?
    @Published public var knownConsoles: [ConsoleProfile] = []

    private let consoles: ConsoleRepository
    private var discoveryTask: Task<Void, Never>?
    private var activeDiscovery: PS4Discovery?

    public init(consoles: ConsoleRepository) {
        self.consoles = consoles
        self.knownConsoles = consoles.consoles
        // The last console is remembered but *not* reported as connected until a new FTP handshake
        // succeeds, so the UI never claims a connection that is not real.
        self.connectedProfile = nil
    }

    /// Infers the /24 broadcast address from the iPhone's Wi-Fi IP so discovery also works on networks
    /// that drop 255.255.255.255.
    private var extraBroadcasts: [String] {
        guard let address = LocalHTTPFileServer.currentWiFiAddress() else { return [] }
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return [] }
        return ["\(parts[0]).\(parts[1]).\(parts[2]).255"]
    }

    public func scan(timeout: TimeInterval = 8) {
        guard status != .searching else { return }
        status = .searching
        discovered = []
        let discovery = PS4Discovery()
        activeDiscovery = discovery
        let options = PS4Discovery.Options(timeout: timeout, searchInterval: 0.8, extraBroadcasts: extraBroadcasts)

        discoveryTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let devices = try discovery.scan(options: options) { device in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if !self.discovered.contains(where: { $0.hostId == device.hostId }) {
                            self.discovered.append(device)
                        }
                    }
                }
                await MainActor.run { [weak self] in
                    self?.lastScanDate = Date()
                    self?.status = .searchingFinished(devices.count)
                    self?.activeDiscovery = nil
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.lastScanDate = Date()
                    self?.status = .failed(message)
                    self?.activeDiscovery = nil
                }
            }
        }
    }

    public func cancelScan() {
        activeDiscovery?.cancel()
        discoveryTask?.cancel()
        activeDiscovery = nil
        if status == .searching { status = .searchingFinished(discovered.count) }
    }

    /// Builds a manual profile from a discovered console (default FTP port 2121, as used by the common
    /// PS4 FTP servers).
    public func profile(for device: PS4Device, port: UInt16 = 2121) -> ConsoleProfile {
        consoles.consoles.first { $0.host == device.address } ?? ConsoleProfile(
            name: device.displayName,
            host: device.address,
            port: port,
            username: "anonymous",
            remotePath: "/",
            isManual: false,
            notes: "Descoberto via DDP • \(device.typeDescription)"
        )
    }

    /// Real FTP login to prove connectivity. Never reports success without a completed handshake.
    public func connect(to profile: ConsoleProfile) {
        if let error = profile.validationError() {
            status = .failed(error)
            return
        }
        status = .connecting(profile.name)
        let host = profile.host
        let port = profile.port
        let user = profile.username
        Task.detached(priority: .userInitiated) { [weak self] in
            let client = FTPClient()
            do {
                try client.connect(host: host, port: port, timeout: 8)
                try client.login(user: user, password: "")
                _ = try? client.systemType()
                client.quitSilently()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.consoles.markConnected(profile)
                    self.knownConsoles = self.consoles.consoles
                    self.connectedProfile = profile
                    self.status = .connected
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.status = .failed(message)
                }
            }
        }
    }

    public func disconnect() {
        connectedProfile = nil
        status = .idle
    }

    public func save(_ profile: ConsoleProfile) {
        consoles.save(profile)
        knownConsoles = consoles.consoles
    }

    public func delete(_ profile: ConsoleProfile) {
        consoles.delete(profile)
        knownConsoles = consoles.consoles
        if connectedProfile?.id == profile.id { connectedProfile = nil }
    }

    /// Quick reachability probe used by the "Conectar" button on an already known console.
    public var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }
}
