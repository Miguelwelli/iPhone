import SwiftUI

/// INÍCIO — hero banner, "Populares" carousel, category chips and "Adicionados Recentemente",
/// following the product reference.
struct HomeView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var transfers: TransferCoordinator
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: SettingsStore

    @State private var selectedCategory: String? = nil
    @State private var showAllPopular = false
    @State private var showAllRecent = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let featured = catalog.featured {
                    HeroBanner(game: featured) {
                        open(featured)
                    }
                } else {
                    EmptyStateView(
                        icon: "gamecontroller",
                        title: "Catálogo vazio",
                        message: "Cadastre jogos no painel administrativo (ícone de cadeado na tela de pesquisa) para começar."
                    )
                }
                popularSection
                categoriesSection
                recentSection
                favoritesSection
                if catalog.games.isEmpty {
                    NoticeBanner("Use o painel administrativo para cadastrar seus jogos e links de download .pkg.", kind: .info)
                }
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, NexusTheme.Metrics.screenPadding)
            .padding(.top, 6)
        }
        .background(NexusBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if selectedCategory == nil { selectedCategory = settings.value.homeCategory }
        }
        .onChange(of: selectedCategory) { newValue in
            settings.setHomeCategory(newValue)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                NexusLogoMark(size: 26)
                Text("NEXUS STORE")
                    .font(.system(size: 19, weight: .heavy))
                    .kerning(0.4)
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
            }
            Spacer()
            IconButton(systemName: "magnifyingglass", background: .clear) {
                router.section = .search
            }
            IconButton(systemName: "bell", background: .clear) {
                router.section = .ps4
            }
            Button {
                router.section = .search
                AdminGate.openingFromHome = true
            } label: {
                Circle()
                    .fill(NexusTheme.Palette.surfaceSecondary)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.textSecondary)
                    )
                    .overlay(Circle().stroke(NexusTheme.Palette.red.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Painel administrativo")
        }
        .padding(.top, 4)
    }

    // MARK: - Populares

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Populares", actionTitle: "Ver tudo") {
                showAllPopular = true
            }
            if catalog.popular.isEmpty {
                Text("Nenhum jogo cadastrado ainda.")
                    .font(.system(size: 13))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(catalog.popular.prefix(10)) { game in
                            GamePosterCard(game: game, width: 128) { open(game) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationDestination(isPresented: $showAllPopular) {
            CatalogView(catalog: catalog, router: router, initialCategory: nil, title: "Populares", subtitle: "Os jogos mais bem avaliados do catálogo")
        }
    }

    // MARK: - Categorias

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Categorias")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    NexusChip(title: "Todos", systemImage: "star.fill", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(GameCategory.all) { category in
                        NexusChip(title: category.title, isSelected: selectedCategory == category.rawValue) {
                            selectedCategory = selectedCategory == category.rawValue ? nil : category.rawValue
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if let selectedCategory {
                let results = catalog.games.filter { $0.categories.contains(selectedCategory) }
                if results.isEmpty {
                    Text("Nenhum jogo nesta categoria.")
                        .font(.system(size: 13))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(results) { game in
                                GamePosterCard(game: game, width: 112) { open(game) }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedCategory)
    }

    // MARK: - Recentes

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Adicionados Recentemente", actionTitle: "Ver tudo") {
                showAllRecent = true
            }
            if catalog.recentlyAdded.isEmpty {
                Text("Os jogos que você cadastrar aparecem aqui.")
                    .font(.system(size: 13))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                    ForEach(catalog.recentlyAdded.prefix(4)) { game in
                        GameWideCard(game: game) { open(game) }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showAllRecent) {
            CatalogView(catalog: catalog, router: router, initialCategory: nil, title: "Recentes", subtitle: "Últimos jogos adicionados", initialSort: .recent)
        }
    }

    // MARK: - Favoritos

    @ViewBuilder
    private var favoritesSection: some View {
        if !catalog.favoriteGames.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Seus favoritos")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(catalog.favoriteGames) { game in
                            GamePosterCard(game: game, width: 112) { open(game) }
                        }
                    }
                }
            }
        }
    }

    private func open(_ game: Game) {
        catalog.recordView(game)
        router.open(game, from: .home)
    }
}

/// 16:9 hero card with "DESTAQUE" badge, title, metadata and the red "VER DETALHES" action.
struct HeroBanner: View {
    let game: Game
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(game: game, banner: true)
                    .frame(height: 268)
                    .frame(maxWidth: .infinity)
                    .overlay(NexusTheme.Palette.heroScrim)
                    .overlay(
                        LinearGradient(colors: [Color.black.opacity(0.45), .clear], startPoint: .top, endPoint: .center)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    NexusBadge("DESTAQUE")
                    Text(game.name.uppercased())
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                    HStack(spacing: 6) {
                        if game.rating > 0 {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(NexusTheme.Palette.warning)
                            Text(game.ratingText)
                                .font(.system(size: 12, weight: .semibold))
                            if !game.ratingCountText.isEmpty {
                                Text("(\(game.ratingCountText))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                            }
                            Text("•").foregroundStyle(NexusTheme.Palette.textTertiary)
                        }
                        Text(game.categoryLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NexusTheme.Palette.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        Text("VER DETALHES")
                            .font(.system(size: 13, weight: .bold))
                            .kerning(0.6)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(NexusTheme.Palette.redGradient)
                    )
                    .padding(.top, 6)
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: NexusTheme.Metrics.largeRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Metrics.largeRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 24, y: 14)
        }
        .buttonStyle(.plain)
    }
}

/// Hexagon logo mark used in the header (drawn with Shape, no asset needed).
struct NexusLogoMark: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            HexagonShape()
                .fill(NexusTheme.Palette.redGradient)
                .frame(width: size, height: size)
            HexagonShape()
                .stroke(Color.black.opacity(0.35), lineWidth: 1)
                .frame(width: size, height: size)
            HexagonShape()
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
                .frame(width: size * 0.55, height: size * 0.55)
        }
        .shadow(color: NexusTheme.Palette.red.opacity(0.6), radius: 8)
    }
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3 - .pi / 2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Tiny helper so the home header can deep-link the admin panel.
enum AdminGate {
    static var openingFromHome = false
}
