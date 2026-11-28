import SwiftUI

/// JOGOS — full catalog with search field, category chips, sorting, filters and a two-column grid.
struct CatalogView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var router: AppRouter
    var initialCategory: String?
    var title: String = "Catálogo"
    var subtitle: String = "Explorar jogos para PS4"
    var initialSort: CatalogSort = .popular

    @State private var searchText = ""
    @State private var selectedCategories: Set<String> = []
    @State private var sort: CatalogSort = .popular
    @State private var showFilters = false
    @State private var favoritesOnly = false
    @State private var didApplyInitial = false

    private var hasActiveFilters: Bool { activeFilterCount > 0 }

    private func clearFilters() {
        searchText = ""
        selectedCategories.removeAll()
        favoritesOnly = false
    }

    private var activeFilterCount: Int {
        var count = selectedCategories.count
        if favoritesOnly { count += 1 }
        if !searchText.isEmpty { count += 1 }
        return count
    }

    private var results: [Game] {
        let games = catalog.filtered(CatalogFilter(searchText: searchText, categories: selectedCategories, sort: sort))
        guard favoritesOnly else { return games }
        return games.filter { catalog.favorites.contains($0.id) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchField
                chipRow
                resultsHeader
                grid
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, NexusTheme.Metrics.screenPadding)
            .padding(.top, 8)
        }
        .background(NexusBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !didApplyInitial else { return }
            didApplyInitial = true
            sort = initialSort
            if let initialCategory {
                selectedCategories = [initialCategory]
            }
        }
        .sheet(isPresented: $showFilters) {
            NexusSheetChrome {
                FiltersSheet(
                    selected: $selectedCategories,
                    sort: $sort,
                    favoritesOnly: $favoritesOnly,
                    total: catalog.games.count
                )
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(NexusTheme.Typography.screenTitle)
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
            }
            Spacer()
            Button {
                showFilters = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    Text(activeFilterCount > 0 ? "Filtros (\(activeFilterCount))" : "Filtros")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(activeFilterCount > 0 ? NexusTheme.Palette.redBright : NexusTheme.Palette.textTertiary)
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
            TextField("Buscar jogos, séries, expansões…", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
                .onTapGesture { showFilters = true }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NexusTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
        )
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NexusChip(title: "Populares", systemImage: "star.fill", isSelected: sort == .popular && selectedCategories.isEmpty) {
                    sort = .popular
                    selectedCategories.removeAll()
                }
                NexusChip(title: "Novidades", isSelected: sort == .recent) {
                    sort = .recent
                }
                ForEach(GameCategory.all.prefix(6)) { category in
                    NexusChip(title: category.title, isSelected: selectedCategories.contains(category.rawValue)) {
                        toggle(category.rawValue)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var resultsHeader: some View {
        HStack(alignment: .center) {
            Text("\(results.count) \(results.count == 1 ? "Jogo encontrado" : "Jogos encontrados")")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
            Spacer()
            Menu {
                ForEach(CatalogSort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if option == sort {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text("Ordenar por:")
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    Text(sort.title)
                        .foregroundStyle(NexusTheme.Palette.redBright)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(NexusTheme.Palette.redBright)
                }
                .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private var grid: some View {
        Group {
            if results.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Nenhum jogo encontrado",
                    message: searchText.isEmpty
                        ? "Ajuste os filtros ou cadastre novos jogos no painel administrativo."
                        : "Nenhum resultado para “\(searchText)”. Tente outro termo.",
                    actionTitle: activeFilterCount > 0 ? "Limpar filtros" : nil,
                    action: hasActiveFilters ? clearFilters : nil
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 18)], spacing: 20) {
                    ForEach(results) { game in
                        GameGridCard(
                            game: game,
                            isFavorite: catalog.isFavorite(game),
                            onFavorite: { catalog.toggleFavorite(game) },
                            onOpen: { open(game) }
                        )
                    }
                }
            }
        }
    }

    private func toggle(_ category: String) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    private func open(_ game: Game) {
        catalog.recordView(game)
        router.open(game, from: router.section)
    }
}

/// Bottom sheet with the full filter set.
struct FiltersSheet: View {
    @Binding var selected: Set<String>
    @Binding var sort: CatalogSort
    @Binding var favoritesOnly: Bool
    let total: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Filtros")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    Spacer()
                    Button {
                        selected.removeAll()
                        favoritesOnly = false
                        sort = .popular
                    } label: {
                        Text("Limpar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.redBright)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("ORDENAR POR")
                        .font(NexusTheme.Typography.tiny)
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    ForEach(CatalogSort.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                                Spacer()
                                if sort == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(NexusTheme.Palette.redBright)
                                }
                            }
                            .font(.system(size: 14, weight: .medium))
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("CATEGORIAS")
                        .font(NexusTheme.Typography.tiny)
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(GameCategory.all) { category in
                            NexusChip(title: category.title, isSelected: selected.contains(category.rawValue)) {
                                if selected.contains(category.rawValue) {
                                    selected.remove(category.rawValue)
                                } else {
                                    selected.insert(category.rawValue)
                                }
                            }
                        }
                    }
                }

                Toggle(isOn: $favoritesOnly) {
                    Label("Somente favoritos", systemImage: "heart.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                }
                .tint(NexusTheme.Palette.red)

                Text("\(total) jogos no catálogo")
                    .font(.system(size: 12))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)

                Button("Aplicar filtros") { dismiss() }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .padding(.top, 4)
            }
            .padding(20)
        }
    }
}
