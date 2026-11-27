import SwiftUI

/// Shared chrome for bottom sheets.
///
/// The app targets iOS 16, where `presentationBackground` is not available (iOS 16.4+) and the sheet
/// would otherwise inherit the system background. Each sheet therefore paints its own black surface
/// with a rounded top and a grabber, matching the product reference.
struct NexusSheetChrome<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            NexusTheme.Palette.backgroundElevated.ignoresSafeArea()
            RadialGradient(
                colors: [NexusTheme.Palette.red.opacity(0.10), .clear],
                center: .init(x: 0.5, y: 0),
                startRadius: 4,
                endRadius: 240
            )
            .ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 38, height: 4)
                    .padding(.top, 8)
                content
            }
        }
        .preferredColorScheme(.dark)
    }
}
