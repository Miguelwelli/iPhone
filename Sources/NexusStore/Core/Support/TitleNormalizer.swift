import Foundation

/// Canonical title form used for duplicate detection.
///
/// "Sekiro: Shadows Die Twice" and "sekiro shadows die twice" must be considered the same game, both
/// when the assistant filters new results and when the catalog rejects a duplicate name.
public enum TitleNormalizer {

    public static func normalize(_ raw: String) -> String {
        let folded = raw.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "pt_BR")
        )
        let allowed = CharacterSet.alphanumerics
        return String(folded.unicodeScalars.filter { allowed.contains($0) })
    }

    /// True when both titles refer to the same game (normalized equality or containment for
    /// subtitled editions such as "The Last of Us Part II" vs "The Last of Us Part II Remastered").
    public static func areEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalize(lhs)
        let b = normalize(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        return shorter.count >= 8 && longer.hasPrefix(shorter)
    }
}
