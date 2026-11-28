import Foundation

public extension CatalogRepository {
    /// In-memory fallback used only when the on-disk catalog cannot be opened at all.
    /// It behaves like a normal repository but writes to a throwaway temporary file.
    static func empty(fileManager: FileManager = .default) -> CatalogRepository {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("nexusstore-fallback-\(UUID().uuidString)")
            .appendingPathComponent("catalog.json")
        // The initializer only fails when the directory cannot be created, which cannot happen here.
        return try! CatalogRepository(fileURL: url, fileManager: fileManager)
    }
}

/// Password-based gate for the admin area.
///
/// The app never stores the password itself: only a salted SHA-256 digest (via CryptoKit on Apple
/// platforms, a small built-in SHA-256 implementation elsewhere so the shared core stays testable).
/// On first launch the admin area asks the user to create a password.
public enum AdminCredential {

    public static let minimumLength = 4

    public static func makeSalt() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    public static func hash(password: String, salt: String) -> String {
        SHA256Hash.hex(SHA256Hash.digest(Data((salt + password).utf8)))
    }

    public static func validate(password: String) -> String? {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < minimumLength {
            return "A senha precisa ter pelo menos \(minimumLength) caracteres."
        }
        if trimmed != password {
            return "A senha não pode começar ou terminar com espaços."
        }
        return nil
    }
}
