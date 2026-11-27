import Foundation
#if !os(Linux)
import Security
#endif

/// Stores the metadata API key in the iOS Keychain (never in UserDefaults, never in the repository).
///
/// A tiny protocol keeps the assistant testable on Linux and in unit tests without touching the
/// Security framework.
public protocol APIKeyStoring: AnyObject {
    func apiKey() -> String?
    func save(_ key: String) throws
    func delete()
}

#if !os(Linux)
public enum APIKeyStoreError: LocalizedError {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Não foi possível gravar a chave no Keychain (código \(status))."
        }
    }
}
#endif

/// In-memory implementation used by tests and previews.
public final class InMemoryAPIKeyStore: APIKeyStoring {
    private var value: String?
    public init(value: String? = nil) { self.value = value }
    public func apiKey() -> String? { value }
    public func save(_ key: String) throws { value = key }
    public func delete() { value = nil }
}

#if !os(Linux)
public final class KeychainAPIKeyStore: APIKeyStoring {

    private let service: String
    private let account: String

    public init(service: String = "com.nexusstore.app.metadata", account: String = "rawg-api-key") {
        self.service = service
        self.account = account
    }

    public func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete()
            return
        }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw APIKeyStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw APIKeyStoreError.keychain(status)
        }
    }

    public func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
#endif
