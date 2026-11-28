import SwiftUI
import UIKit

/// The five navigation destinations from the product reference.
public enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case games
    case categories
    case search
    case ps4

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Início"
        case .games: return "Jogos"
        case .categories: return "Categorias"
        case .search: return "Pesquisa"
        case .ps4: return "PS4"
        }
    }

    public var icon: String {
        switch self {
        case .home: return "house.fill"
        case .games: return "gamecontroller.fill"
        case .categories: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .ps4: return "playstation.logo"
        }
    }
}

/// Custom floating tab bar with the red active state and dot indicator from the reference.
public struct NexusTabBar: View {
    @Binding var selection: AppSection
    var transferBadge: Bool
    var transferProgress: Double?

    public init(selection: Binding<AppSection>, transferBadge: Bool = false, transferProgress: Double? = nil) {
        _selection = selection
        self.transferBadge = transferBadge
        self.transferProgress = transferProgress
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(AppSection.allCases) { section in
                Button {
                    guard selection != section else { return }
                    let generator = UIImpactFeedbackGenerator(style: .soft)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        selection = section
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Image(systemName: section.icon)
                                .font(.system(size: 19, weight: selection == section ? .semibold : .regular))
                                .foregroundStyle(selection == section ? NexusTheme.Palette.redBright : NexusTheme.Palette.textTertiary)
                                .symbolRenderingMode(.hierarchical)
                            if section == .ps4, let progress = transferProgress {
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(NexusTheme.Palette.redBright, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                                    .frame(width: 28, height: 28)
                                    .rotationEffect(.degrees(-90))
                            }
                            if section == .ps4, transferBadge, transferProgress == nil {
                                Circle()
                                    .fill(NexusTheme.Palette.redBright)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 13, y: -9)
                            }
                        }
                        .frame(height: 24)
                        Text(section.title)
                            .font(.system(size: 10.5, weight: selection == section ? .semibold : .medium))
                            .foregroundStyle(selection == section ? NexusTheme.Palette.redBright : NexusTheme.Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .padding(.horizontal, 8)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(NexusTheme.Palette.background.opacity(0.82))
            }
            .overlay(alignment: .top) {
                Rectangle().fill(NexusTheme.Palette.stroke).frame(height: 0.6)
            }
        )
    }
}
