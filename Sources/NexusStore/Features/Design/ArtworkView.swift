import SwiftUI
import UIKit

/// Renders cover/banner artwork with a graceful fallback.
///
/// - `https://` references are loaded with `AsyncImage` (disk-cached by URLSession), showing a
///   shimmer while loading and the generated placeholder if it fails.
/// - Bundled references (demo catalog) resolve to PNG assets shipped in the app.
/// - The fallback is a designed placeholder with the game's initials — never a blank rectangle.
public struct ArtworkView: View {
    let reference: ArtworkReference
    let initials: String
    var contentMode: ContentMode = .fill

    public init(reference: ArtworkReference, initials: String, contentMode: ContentMode = .fill) {
        self.reference = reference
        self.initials = initials
        self.contentMode = contentMode
    }

    public init(game: Game, banner: Bool = false) {
        self.init(
            reference: banner ? game.bannerArtwork : game.coverArtwork,
            initials: Self.initials(for: game.name)
        )
    }

    public var body: some View {
        Group {
            switch reference {
            case .remote(let url):
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay(ProgressView().tint(NexusTheme.Palette.redBright))
                    @unknown default:
                        placeholder
                    }
                }
            case .bundled(let name):
                if let uiImage = UIImage(named: name) {
                    Image(uiImage: uiImage).resizable().aspectRatio(contentMode: contentMode)
                } else {
                    placeholder
                }
            case .none:
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [NexusTheme.Palette.surfaceSecondary, NexusTheme.Palette.backgroundElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [NexusTheme.Palette.red.opacity(0.22), .clear],
                center: .init(x: 0.25, y: 0.2),
                startRadius: 2,
                endRadius: 160
            )
            Text(initials)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "NS" : letters.uppercased()
    }
}

/// 2:3 cover thumbnail with rounded corners + border, exactly like the catalog cards.
public struct CoverThumbnail: View {
    let game: Game
    var width: CGFloat = 104
    var cornerRadius: CGFloat = 12

    public init(game: Game, width: CGFloat = 104, cornerRadius: CGFloat = 12) {
        self.game = game
        self.width = width
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ArtworkView(game: game)
            .frame(width: width, height: width / NexusTheme.Metrics.coverRatio)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}
