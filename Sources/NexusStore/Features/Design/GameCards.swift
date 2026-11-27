import SwiftUI

/// Vertical catalog tile: 2:3 cover, title, size/rating and category chips underneath
/// (the "Catálogo" layout from the reference).
public struct GameGridCard: View {
    let game: Game
    var isFavorite: Bool
    var showFavoriteButton: Bool = true
    var onFavorite: (() -> Void)?
    let onOpen: () -> Void

    public init(game: Game, isFavorite: Bool, showFavoriteButton: Bool = true, onFavorite: (() -> Void)? = nil, onOpen: @escaping () -> Void) {
        self.game = game
        self.isFavorite = isFavorite
        self.showFavoriteButton = showFavoriteButton
        self.onFavorite = onFavorite
        self.onOpen = onOpen
    }

    public var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    ArtworkView(game: game)
                        .aspectRatio(NexusTheme.Metrics.coverRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if showFavoriteButton {
                        IconButton(
                            systemName: isFavorite ? "heart.fill" : "heart",
                            tint: isFavorite ? NexusTheme.Palette.redBright : .white,
                            background: Color.black.opacity(0.45),
                            size: 30,
                            action: { onFavorite?() }
                        )
                        .padding(8)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if SeedCatalog.isSample(game) {
                        NexusBadge("DEMO", style: .neutral).padding(8)
                    }
                }

                Text(game.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 9)

                HStack(spacing: 8) {
                    Text(ByteFormatting.formatSize(game.byteCount))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    if game.rating > 0 {
                        RatingLabel(rating: game.rating)
                    }
                }
                .padding(.top, 3)

                Text(game.categoryLine)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(NexusTheme.Palette.surfaceSecondary))
                    .padding(.top, 7)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Compact vertical tile used by the horizontal "Populares" row on the home screen.
public struct GamePosterCard: View {
    let game: Game
    var width: CGFloat = 132
    let onOpen: () -> Void

    public init(game: Game, width: CGFloat = 132, onOpen: @escaping () -> Void) {
        self.game = game
        self.width = width
        self.onOpen = onOpen
    }

    public var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ArtworkView(game: game)
                    .frame(width: width, height: width / NexusTheme.Metrics.coverRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
                    )
                Text(game.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                    .lineLimit(2)
                    .frame(width: width, alignment: .leading)
                HStack(spacing: 6) {
                    Text(ByteFormatting.formatSize(game.byteCount))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    RatingLabel(rating: game.rating)
                }
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
    }
}

/// Wide 16:9 card used by the "Adicionados Recentemente" row.
public struct GameWideCard: View {
    let game: Game
    let onOpen: () -> Void

    public init(game: Game, onOpen: @escaping () -> Void) {
        self.game = game
        self.onOpen = onOpen
    }

    public var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ArtworkView(game: game, banner: true)
                    .aspectRatio(NexusTheme.Metrics.bannerRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
                    )
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.textPrimary)
                            .lineLimit(1)
                        Text(ByteFormatting.formatSize(game.byteCount))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NexusTheme.Palette.textTertiary)
                    }
                    Spacer(minLength: 4)
                    NexusBadge(game.platformTag.isEmpty ? "PS4" : game.platformTag, style: .neutral)
                }
                .padding(.top, 9)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal admin row with cover, metadata and edit/delete actions.
public struct AdminGameRow: View {
    let game: Game
    let onEdit: () -> Void
    let onDelete: () -> Void

    public init(game: Game, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.game = game
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 12) {
            CoverThumbnail(game: game, width: 48, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(ByteFormatting.formatSize(game.byteCount))
                    Text("•")
                    Text("v\(game.version)")
                    Text("•")
                    Text(game.categoryLine)
                        .lineLimit(1)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
            Spacer(minLength: 6)
            Button(action: onEdit) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.danger)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}
