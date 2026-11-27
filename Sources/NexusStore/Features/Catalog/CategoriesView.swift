import SwiftUI

/// CATEGORIAS — grid of category cards with real counts, plus shortcuts to favorites and recents.
struct CategoriesView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var router: AppRouter

    @State private var selected: GameCategory?
    @State private var showCategory = false
    @State private var showFavorites = false
    @State private var showRecents = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Categorias")
                    .font(NexusTheme.Typography.screenTitle)
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Text("Navegue pelo catálogo por gênero")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(GameCategory.all) { category in
                        CategoryCard(category: category, count: catalog.count(for: category.rawValue)) {
                            selected = category
                            showCategory = true
                        }
                    }
                }

                SectionHeader("Sua biblioteca")
                HStack(spacing: 12) {
                    libraryTile(title: "Favoritos", value: "\(catalog.favoriteGames.count)", icon: "heart.fill") {
                        showFavorites = true
                    }
                    libraryTile(title: "Recentes", value: "\(catalog.recentlyViewed.count)", icon: "clock.fill") {
                        showRecents = true
                    }
                }

                if catalog.games.isEmpty {
                    NoticeBanner("Cadastre jogos no painel administrativo para preencher as categorias.", kind: .info)
                }
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, NexusTheme.Metrics.screenPadding)
            .padding(.top, 8)
        }
        .background(NexusBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showCategory) {
            if let selected {
                CatalogView(
                    catalog: catalog,
                    router: router,
                    initialCategory: selected.rawValue,
                    title: selected.title,
                    subtitle: "Jogos em \(selected.title)"
                )
            }
        }
        .navigationDestination(isPresented: $showFavorites) {
            FavoritesView(catalog: catalog, router: router)
        }
        .navigationDestination(isPresented: $showRecents) {
            RecentlyViewedView(catalog: catalog, router: router)
        }
    }

    private func libraryTile(title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.redBright)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NexusTheme.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct CategoryCard: View {
    let category: GameCategory
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.redBright)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(NexusTheme.Palette.red.opacity(0.14)))
                Text(category.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Text(count == 1 ? "1 jogo" : "\(count) jogos")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                    .fill(NexusTheme.Palette.cardGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                    .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FavoritesView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var router: AppRouter

    var body: some View {
        CatalogScaffoldList(
            title: "Favoritos",
            subtitle: "Seus jogos salvos",
            games: catalog.favoriteGames,
            emptyMessage: "Toque no coração de um jogo para salvá-lo aqui.",
            catalog: catalog,
            router: router
        )
    }
}

struct RecentlyViewedView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var router: AppRouter

    var body: some View {
        CatalogScaffoldList(
            title: "Vistos recentemente",
            subtitle: "Histórico de navegação",
            games: catalog.recentlyViewed,
            emptyMessage: "Abra um jogo para vê-lo aqui.",
            catalog: catalog,
            router: router
        )
    }
}

/// Reusable grid screen for simple game lists (favorites, recents, search results).
struct CatalogScaffoldList: View {
    let title: String
    let subtitle: String
    let games: [Game]
    let emptyMessage: String
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var router: AppRouter

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(NexusTheme.Typography.screenTitle)
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                if games.isEmpty {
                    EmptyStateView(icon: "tray", title: "Nada por aqui", message: emptyMessage)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 18)], spacing: 20) {
                        ForEach(games) { game in
                            GameGridCard(
                                game: game,
                                isFavorite: catalog.isFavorite(game),
                                onFavorite: { catalog.toggleFavorite(game) },
                                onOpen: {
                                    catalog.recordView(game)
                                    router.open(game, from: router.section)
                                }
                            )
                        }
                    }
                }
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, NexusTheme.Metrics.screenPadding)
            .padding(.top, 8)
        }
        .background(NexusBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}
