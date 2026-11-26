import SwiftUI

enum NexusTheme {
    static let bgBlack = Color(red: 0.03, green: 0.04, blue: 0.08)
    static let bgDarkBlue = Color(red: 0.05, green: 0.10, blue: 0.22)
    static let cardSurface = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.12)
    static let electricBlue = Color(red: 0.00, green: 0.44, blue: 0.88)
    static let electricGlow = Color(red: 0.12, green: 0.62, blue: 1.00)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let successGreen = Color(red: 0.18, green: 0.82, blue: 0.52)
    static let errorRed = Color(red: 0.96, green: 0.30, blue: 0.34)
    static let warningAmber = Color(red: 0.98, green: 0.72, blue: 0.20)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [bgBlack, bgDarkBlue, bgBlack],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct NexusCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(NexusTheme.cardSurface)
                    .background(.ultraThinMaterial.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NexusTheme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func nexusCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(NexusCardModifier(cornerRadius: cornerRadius))
    }
}
