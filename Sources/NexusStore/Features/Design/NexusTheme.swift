import SwiftUI

/// Nexus Store design tokens.
///
/// The palette is taken from the product reference: deep black background, graphite cards, a single
/// elegant red accent and white typography. Everything visual is defined here so the app stays
/// consistent and re-themeable.
public enum NexusTheme {

    // MARK: Colors

    public enum Palette {
        /// Screen background (#050506).
        public static let background = Color(red: 5 / 255, green: 5 / 255, blue: 6 / 255)
        /// Slightly lifted background used behind grouped content.
        public static let backgroundElevated = Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255)
        /// Card surface (graphite).
        public static let surface = Color(red: 22 / 255, green: 22 / 255, blue: 25 / 255)
        /// Secondary surface for inputs and tiles.
        public static let surfaceSecondary = Color(red: 30 / 255, green: 30 / 255, blue: 34 / 255)
        /// 1 pt separators and card borders.
        public static let stroke = Color.white.opacity(0.08)
        public static let strokeStrong = Color.white.opacity(0.14)

        /// Primary brand red.
        public static let red = Color(red: 228 / 255, green: 0 / 255, blue: 43 / 255)
        /// Brighter red for gradients/highlights.
        public static let redBright = Color(red: 255 / 255, green: 32 / 255, blue: 66 / 255)
        /// Dark red used for pressed states and glows.
        public static let redDeep = Color(red: 120 / 255, green: 0 / 255, blue: 20 / 255)

        public static let textPrimary = Color.white
        public static let textSecondary = Color.white.opacity(0.62)
        public static let textTertiary = Color.white.opacity(0.38)

        public static let success = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
        public static let warning = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
        public static let danger = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)

        public static let cardGradient = LinearGradient(
            colors: [Color(red: 26 / 255, green: 26 / 255, blue: 30 / 255),
                     Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        public static let redGradient = LinearGradient(
            colors: [redBright, red],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        public static let heroScrim = LinearGradient(
            colors: [.clear, Color.black.opacity(0.35), Color.black.opacity(0.92)],
            startPoint: .center,
            endPoint: .bottom
        )
    }

    // MARK: Type scale

    public enum Typography {
        public static func display(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .heavy, design: .default) }
        public static let screenTitle = Font.system(size: 32, weight: .bold)
        public static let sectionTitle = Font.system(size: 20, weight: .bold)
        public static let cardTitle = Font.system(size: 15, weight: .semibold)
        public static let body = Font.system(size: 15, weight: .regular)
        public static let caption = Font.system(size: 12, weight: .medium)
        public static let tiny = Font.system(size: 10, weight: .semibold)
        public static let button = Font.system(size: 16, weight: .bold)
        public static let number = Font.system(size: 28, weight: .bold, design: .rounded)
    }

    // MARK: Metrics

    public enum Metrics {
        public static let screenPadding: CGFloat = 20
        public static let cardRadius: CGFloat = 18
        public static let largeRadius: CGFloat = 26
        public static let buttonHeight: CGFloat = 54
        public static let tabBarHeight: CGFloat = 64
        public static let coverRatio: CGFloat = 2.0 / 3.0
        public static let bannerRatio: CGFloat = 16.0 / 9.0
    }
}

// MARK: - Background

/// Full-screen background: near-black with a very subtle red glow at the top, like the reference.
public struct NexusBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            NexusTheme.Palette.background
            RadialGradient(
                colors: [NexusTheme.Palette.red.opacity(0.16), .clear],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 8,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.white.opacity(0.03), .clear],
                center: .init(x: 0.9, y: 0.15),
                startRadius: 4,
                endRadius: 260
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
