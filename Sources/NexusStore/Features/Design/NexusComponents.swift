import SwiftUI

// MARK: - Buttons

/// Full-width red action button with the brand gradient and a soft glow.
public struct PrimaryActionButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NexusTheme.Typography.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: NexusTheme.Metrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NexusTheme.Palette.redGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: NexusTheme.Palette.red.opacity(configuration.isPressed ? 0.25 : 0.45), radius: 18, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Outlined secondary button (e.g. "Buscar novamente").
public struct SecondaryActionButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NexusTheme.Typography.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: NexusTheme.Metrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NexusTheme.Palette.surface.opacity(configuration.isPressed ? 0.9 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NexusTheme.Palette.red.opacity(0.55), lineWidth: 1.2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Compact circular icon button used in navigation bars and cards.
public struct IconButton: View {
    let systemName: String
    let action: () -> Void
    var tint: Color = .white
    var background: Color = NexusTheme.Palette.surfaceSecondary.opacity(0.9)
    var size: CGFloat = 38

    public init(systemName: String, tint: Color = .white, background: Color = NexusTheme.Palette.surfaceSecondary.opacity(0.9), size: CGFloat = 38, action: @escaping () -> Void) {
        self.systemName = systemName
        self.tint = tint
        self.background = background
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .overlay(Circle().stroke(NexusTheme.Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chips

/// Category / filter pill. `selected` renders the reference's red "Todos" style.
public struct NexusChip: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool
    var action: () -> Void

    public init(title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? .white : NexusTheme.Palette.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(NexusTheme.Palette.redGradient) : AnyShapeStyle(NexusTheme.Palette.surface))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.14) : NexusTheme.Palette.stroke, lineWidth: 1)
            )
            .shadow(color: isSelected ? NexusTheme.Palette.red.opacity(0.35) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badges

public struct NexusBadge: View {
    public enum Style { case red, green, neutral, warning }

    let text: String
    var style: Style = .red

    public init(_ text: String, style: Style = .red) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .font(NexusTheme.Typography.tiny)
            .kerning(0.6)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .overlay(Capsule().stroke(foreground.opacity(0.35), lineWidth: 0.8))
    }

    private var foreground: Color {
        switch style {
        case .red: return Color.white
        case .green: return NexusTheme.Palette.success
        case .neutral: return NexusTheme.Palette.textSecondary
        case .warning: return NexusTheme.Palette.warning
        }
    }

    private var background: Color {
        switch style {
        case .red: return NexusTheme.Palette.red
        case .green: return NexusTheme.Palette.success.opacity(0.16)
        case .neutral: return NexusTheme.Palette.surfaceSecondary
        case .warning: return NexusTheme.Palette.warning.opacity(0.16)
        }
    }
}

// MARK: - Section header

public struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(NexusTheme.Typography.sectionTitle)
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.redBright)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Surfaces

/// Graphite card container used by every list row/tile.
public struct NexusCard<Content: View>: View {
    var cornerRadius: CGFloat = NexusTheme.Metrics.cardRadius
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    public init(cornerRadius: CGFloat = NexusTheme.Metrics.cardRadius, padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(NexusTheme.Palette.cardGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
            )
    }
}

/// Label + value tile (the "48.5 GB / Tamanho" boxes in the product reference).
public struct StatTile: View {
    let value: String
    let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NexusTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Rating

public struct RatingLabel: View {
    let rating: Double
    var count: String?

    public init(rating: Double, count: String? = nil) {
        self.rating = rating
        self.count = count
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(NexusTheme.Palette.warning)
            Text(String(format: "%.1f", rating))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            if let count, !count.isEmpty {
                Text("(\(count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
        }
    }
}

// MARK: - Empty state

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    public init(icon: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NexusTheme.Palette.redBright.opacity(0.85))
                .padding(.bottom, 4)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.redBright)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                .fill(NexusTheme.Palette.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Banner

/// Slim inline banner used for errors/warnings (honest reporting instead of silent failures).
public struct NoticeBanner: View {
    public enum Kind { case info, warning, error, success }

    let text: String
    var kind: Kind = .info

    public init(_ text: String, kind: Kind = .info) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }

    private var icon: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .success: return "checkmark.seal.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .info: return NexusTheme.Palette.redBright
        case .warning: return NexusTheme.Palette.warning
        case .error: return NexusTheme.Palette.danger
        case .success: return NexusTheme.Palette.success
        }
    }
}
