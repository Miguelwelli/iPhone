import SwiftUI

/// PESQUISA — instant search with suggestions, recent searches and the entry point to the admin panel.
struct SearchView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var router: AppRouter
    let preferences: PreferencesStore
    /// Search is the tab that opens the admin panel, which needs the transfer coordinator for its
    /// settings entry point.
    @ObservedObject var transfers: TransferCoordinator

    @EnvironmentObject private var session: AdminSession
    @EnvironmentObject private var settings: SettingsStore
    @State private var query = ""
    @State private var showAdmin = false
    @FocusState private var isFocused: Bool

    private var results: [Game] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return catalog.filtered(CatalogFilter(searchText: query, sort: .popular))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestions
                    adminCard
                } else {
                    resultList
                }
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, NexusTheme.Metrics.screenPadding)
            .padding(.top, 8)
        }
        .background(NexusBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if AdminGate.openingFromHome {
                AdminGate.openingFromHome = false
                showAdmin = true
            }
        }
        .navigationDestination(isPresented: $showAdmin) {
            AdminView(
                catalog: catalog,
                preferences: preferences,
                session: session,
                transfers: transfers
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pesquisa")
                    .font(NexusTheme.Typography.screenTitle)
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Text("Encontre qualquer jogo do catálogo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
            }
            Spacer()
            Button {
                showAdmin = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    Text("Admin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            TextField("Buscar jogos, séries, expansões…", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(commitSearch)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NexusTheme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !settings.value.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Buscas recentes")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.textPrimary)
                        Spacer()
                        Button {
                            settings.clearSearches()
                        } label: {
                            Text("Limpar")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NexusTheme.Palette.redBright)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(settings.value.recentSearches, id: \.self) { term in
                        Button {
                            query = term
                            commitSearch()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(NexusTheme.Palette.textTertiary)
                                Text(term)
                                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                                Spacer()
                            }
                            .font(.system(size: 14))
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Explorar categorias")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(GameCategory.all) { category in
                        NexusChip(title: category.title, isSelected: false) {
                            query = category.title
                            commitSearch()
                        }
                    }
                }
            }

            if !catalog.popular.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mais buscados")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    ForEach(catalog.popular.prefix(4)) { game in
                        Button {
                            catalog.recordView(game)
                            router.open(game, from: .search)
                        } label: {
                            HStack(spacing: 12) {
                                CoverThumbnail(game: game, width: 40, cornerRadius: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(game.name)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                                        .lineLimit(1)
                                    Text(game.categoryLine)
                                        .font(.system(size: 11))
                                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(NexusTheme.Palette.textTertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(results.count) \(results.count == 1 ? "resultado" : "resultados")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
            if results.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Nenhum resultado",
                    message: "Não encontramos jogos para “\(query)”. Verifique a grafia ou cadastre o jogo no painel administrativo."
                )
            } else {
                ForEach(results) { game in
                    Button {
                        commitSearch()
                        catalog.recordView(game)
                        router.open(game, from: .search)
                    } label: {
                        HStack(spacing: 12) {
                            CoverThumbnail(game: game, width: 52, cornerRadius: 9)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(game.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(ByteFormatting.formatSize(game.byteCount))
                                    Text("•")
                                    Text(game.categoryLine).lineLimit(1)
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(NexusTheme.Palette.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NexusTheme.Palette.textTertiary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NexusTheme.Palette.surface.opacity(0.8)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var adminCard: some View {
        Button {
            showAdmin = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.redBright)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(NexusTheme.Palette.red.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Painel Administrativo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    Text("Cadastrar, editar e remover jogos do catálogo")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous).fill(NexusTheme.Palette.cardGradient))
            .overlay(RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func commitSearch() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        settings.recordSearch(term)
        isFocused = false
    }
}
