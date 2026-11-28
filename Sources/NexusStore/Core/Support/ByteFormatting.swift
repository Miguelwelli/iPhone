import Foundation

/// Parses and renders file sizes.
///
/// Accepted inputs (case and accent insensitive, comma or dot decimals):
/// `48.5 GB`, `48,5 gb`, `900 MB`, `1 TB`, `16106127360` (raw bytes).
///
/// Binary units (1 KB = 1024 B) are used, matching what the PlayStation / iOS `ByteCountFormatter`
/// show by default.
public enum ByteFormatting {

    private static let unitTable: [(suffix: String, multiplier: Double)] = [
        ("tb", 1_099_511_627_776),
        ("tib", 1_099_511_627_776),
        ("gb", 1_073_741_824),
        ("gib", 1_073_741_824),
        ("mb", 1_048_576),
        ("mib", 1_048_576),
        ("kb", 1_024),
        ("kib", 1_024),
        ("b", 1)
    ]

    /// Parses a human readable size into bytes. Returns nil when the text is not a valid size.
    public static func parseSize(_ raw: String) -> Int64? {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        guard !text.isEmpty else { return nil }

        // Normalize Brazilian decimal comma: "48,5" -> "48.5"
        text = text.replacingOccurrences(of: ",", with: ".")

        // Lowercase, strip spaces between number and unit, and strip accents.
        text = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        text = text.replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: "bytes", with: "b")

        // Raw byte count (digits only) is interpreted as bytes.
        if text.allSatisfy({ $0.isNumber }), let value = Int64(text) {
            return value
        }

        // Find the longest matching unit suffix.
        for entry in unitTable where text.hasSuffix(entry.suffix) {
            let numberPart = String(text.dropLast(entry.suffix.count))
            guard !numberPart.isEmpty, let number = Double(numberPart), number >= 0 else { return nil }
            let bytes = (number * entry.multiplier).rounded()
            guard bytes.isFinite, bytes >= 0, bytes < Double(Int64.max) else { return nil }
            return Int64(bytes)
        }
        return nil
    }

    /// Renders bytes with GB/MB as appropriate ("48.5 GB").
    public static func formatSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        }
        return "\(bytes) B"
    }

    /// Transfer-speed rendering ("92.4 MB/s").
    public static func formatSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "0 MB/s" }
        let mb = bytesPerSecond / 1_048_576
        if mb >= 1 {
            return String(format: "%.1f MB/s", mb)
        }
        let kb = bytesPerSecond / 1024
        return String(format: "%.0f KB/s", max(kb, 0.1))
    }

    /// Remaining-time rendering ("~5 min", "1h 12 min", "menos de 1 min").
    public static func formatRemaining(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 60 { return "menos de 1 min" }
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 { return "~\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "~\(hours)h" : "~\(hours)h \(minutes) min"
    }

    /// Progress percentage clamped to 0...100.
    public static func percentage(transferred: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        let value = Double(transferred) / Double(total) * 100
        return min(max(value, 0), 100)
    }
}
