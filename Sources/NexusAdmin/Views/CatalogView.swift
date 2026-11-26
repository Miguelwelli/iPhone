import SwiftUI

struct CatalogView: View {
    @ObservedObject var service: SupabaseService
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "Todas"
    @State private var editingGame: Game?
    @State private var gameToDelete: Game?

    private var categories: [String] {
        ["Todas"] + GameCategory.allCases.map(\.rawValue)
    }

    private var filteredGames: [Game] {
        service.games.filter { game in
            let matchesCategory = selectedCategory == "Todas" || game.category == selectedCategory
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                game.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            headerSection
            searchAndFilterSection

            if service.isLoading {
                Spacer()
                ProgressView("Carregando catálogo...")
                    .tint(NexusTheme.electricGlow)
                    .foregroundStyle(NexusTheme.textSecondary)
                Spacer()
            } else if filteredGames.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(NexusTheme.textSecondary)
                    Text(service.games.isEmpty ? "Nenhum jogo cadastrado" : "Nenhum resultado encontrado")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(NexusTheme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredGames) { game in
                            gameCard(game)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await service.fetchGames()
                }
            }
        }
        .background(NexusTheme.backgroundGradient.ignoresSafeArea())
        .sheet(item: $editingGame) { game in
            NavigationStack {
                GameFormView(service: service, editingGame: game) {
                    editingGame = nil
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fechar") { editingGame = nil }
                            .foregroundStyle(NexusTheme.electricGlow)
                    }
                }
            }
        }
        .alert("Excluir publicação?", isPresented: Binding(
            get: { gameToDelete != nil },
            set: { if !$0 { gameToDelete = nil } }
        )) {
            Button("Cancelar", role: .cancel) { gameToDelete = nil }
            Button("Excluir", role: .destructive) {
                if let target = gameToDelete {
                    Task { try? await service.deleteGame(id: target.id) }
                }
                gameToDelete = nil
            }
        } message: {
            Text("Deseja remover \"\(gameToDelete?.name ?? "")\" do catálogo da NEXUS STORE?")
        }
    }

    private var headerSection: some View {
        HStack {
            Text("Catálogo")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(NexusTheme.textPrimary)
            Spacer()
            Text("\(filteredGames.count) jogos")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NexusTheme.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var searchAndFilterSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NexusTheme.textSecondary)
                TextField("Pesquisar jogos...", text: $searchText)
                    .foregroundStyle(NexusTheme.textPrimary)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .nexusCard(cornerRadius: 14)
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            selectedCategory = cat
                        } label: {
                            Text(cat)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    selectedCategory == cat
                                        ? NexusTheme.electricBlue
                                        : Color.white.opacity(0.08)
                                )
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func gameCard(_ game: Game) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: game.cover_url)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "photo")
                            .foregroundStyle(NexusTheme.textSecondary)
                    }
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(game.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NexusTheme.textPrimary)
                    .lineLimit(1)

                Text("\(game.category) • \(game.platform) • \(game.size)")
                    .font(.caption)
                    .foregroundStyle(NexusTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(game.published ? "Publicado" : "Oculto")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (game.published ? NexusTheme.successGreen : NexusTheme.warningAmber)
                                .opacity(0.2)
                        )
                        .foregroundStyle(game.published ? NexusTheme.successGreen : NexusTheme.warningAmber)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    editingGame = game
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundStyle(NexusTheme.electricGlow)
                }

                Button {
                    gameToDelete = game
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                        .foregroundStyle(NexusTheme.errorRed)
                }
            }
        }
        .padding(12)
        .nexusCard(cornerRadius: 16)
    }
}
