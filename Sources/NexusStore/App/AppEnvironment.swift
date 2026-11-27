import Foundation

/// Resolves the on-device storage locations used by the app.
///
/// Named `NexusFileStorage` (not `AppStorage`) to avoid clashing with SwiftUI's `AppStorage` property
/// wrapper, which would be ambiguous at every call site.
///
/// - Catalog, consoles and settings live in `Application Support/NexusStore/` (backed up, not
///   user-visible).
/// - Temporary `.pkg` files live in `Caches/NexusStore/Transfers/` so iOS can purge them if the
///   device is short on space; the app checks the free space before starting a download anyway.
public enum NexusFileStorage {

    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("NexusStore", isDirectory: true)
    }

    public static var caches: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("NexusStore", isDirectory: true)
    }

    public static var catalogFile: URL { applicationSupport.appendingPathComponent("catalog.json") }
    public static var consolesFile: URL { applicationSupport.appendingPathComponent("consoles.json") }
    public static var preferencesFile: URL { applicationSupport.appendingPathComponent("preferences.json") }
    public static var settingsFile: URL { applicationSupport.appendingPathComponent("settings.json") }
    public static var autoCatalogFile: URL { applicationSupport.appendingPathComponent("auto-catalog.json") }
    public static var transfersDirectory: URL { caches.appendingPathComponent("Transfers", isDirectory: true) }

    public static var preferences: PreferencesStore { PreferencesStore(fileURL: preferencesFile) }

    public static func prepare() {
        for directory in [applicationSupport, transfersDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Free space in bytes on the volume that holds temporary downloads.
    public static func freeDiskSpace() -> Int64 {
        let url = transfersDirectory
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
              let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value else {
            return 0
        }
        return free
    }
}

/// App-wide dependency container created once in `NexusStoreApp`.
@MainActor
public final class AppEnvironment {

    public let catalog: CatalogRepository
    public let consoles: ConsoleRepository
    public let preferences: PreferencesStore
    public let transfers: TransferCoordinator
    public let discovery: PS4ConnectionService
    public let settings: SettingsStore
    public let autoCatalog: AutoCatalogStore

    public init() {
        NexusFileStorage.prepare()
        let catalogRepository: CatalogRepository
        do {
            catalogRepository = try CatalogRepository(
                fileURL: NexusFileStorage.catalogFile,
                seed: DemoCatalogBridge.loadFromMainBundle()
            )
        } catch {
            // A corrupted catalog must never prevent the app from launching: start empty and let the
            // admin panel recreate the data. The failure is surfaced in the admin screen.
            catalogRepository = (try? CatalogRepository(fileURL: NexusFileStorage.catalogFile)) ?? CatalogRepository.empty()
        }
        catalog = catalogRepository
        consoles = ConsoleRepository(fileURL: NexusFileStorage.consolesFile)
        preferences = PreferencesStore(fileURL: NexusFileStorage.preferencesFile)
        transfers = TransferCoordinator(
            workingDirectory: NexusFileStorage.transfersDirectory,
            configuration: preferences.value.transferConfiguration
        )
        discovery = PS4ConnectionService(consoles: consoles)
        settings = SettingsStore(fileURL: NexusFileStorage.settingsFile)
        autoCatalog = AutoCatalogStore(
            repository: AutoCatalogRepository(fileURL: NexusFileStorage.autoCatalogFile),
            keyStore: KeychainAPIKeyStore(),
            catalog: CatalogStore(repository: catalog)
        )
    }
}

// MARK: - Console persistence

public final class ConsoleRepository {

    private let fileURL: URL
    public private(set) var consoles: [ConsoleProfile] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        consoles = (try? decoder.decode([ConsoleProfile].self, from: data)) ?? []
    }

    public func save(_ profile: ConsoleProfile) {
        if let index = consoles.firstIndex(where: { $0.id == profile.id }) {
            consoles[index] = profile
        } else if let index = consoles.firstIndex(where: { $0.host == profile.host && $0.port == profile.port }) {
            var updated = profile
            updated.id = consoles[index].id
            consoles[index] = updated
        } else {
            consoles.append(profile)
        }
        persist()
    }

    public func delete(_ profile: ConsoleProfile) {
        consoles.removeAll { $0.id == profile.id }
        persist()
    }

    public func markConnected(_ profile: ConsoleProfile, at date: Date = Date()) {
        var updated = profile
        updated.lastConnectedAt = date
        save(updated)
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(consoles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Preferences

/// Small persisted settings (admin password hash, transfer options, onboarding state).
public struct AppPreferences: Codable, Equatable {
    public var adminPasswordHash: String
    public var adminPasswordSalt: String
    public var transferConfiguration: TransferConfiguration
    public var hasSeenPS4Warning: Bool
    public var lastConsoleID: UUID?

    public init(
        adminPasswordHash: String = "",
        adminPasswordSalt: String = "",
        transferConfiguration: TransferConfiguration = TransferConfiguration(),
        hasSeenPS4Warning: Bool = false,
        lastConsoleID: UUID? = nil
    ) {
        self.adminPasswordHash = adminPasswordHash
        self.adminPasswordSalt = adminPasswordSalt
        self.transferConfiguration = transferConfiguration
        self.hasSeenPS4Warning = hasSeenPS4Warning
        self.lastConsoleID = lastConsoleID
    }

    public var hasAdminPassword: Bool { !adminPasswordHash.isEmpty }
}

public final class PreferencesStore {

    private let fileURL: URL
    public private(set) var value: AppPreferences

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            value = decoded
        } else {
            value = AppPreferences()
        }
    }

    public func update(_ mutate: (inout AppPreferences) -> Void) {
        mutate(&value)
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(value) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
