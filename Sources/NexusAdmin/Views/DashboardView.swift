import SwiftUI

struct DashboardView: View {
    @ObservedObject var service: SupabaseService
    var onNavigateToCreate: () -> Void
    var onNavigateToCatalog: () -> Void
    var onOpenSettings: () -> Void

    private var publishedCount: Int {
        service.games.filter(\.published).count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                statsSection
                shortcutsSection
                recentGamesSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(NexusTheme.backgroundGradient.ignoresSafeArea())
        .refreshable {
            await service.fetchGames()
        }
    }

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [NexusTheme.electricBlue, NexusTheme.electricGlow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("NEXUS ADMIN")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(NexusTheme.textPrimary)
                Text("Painel Oficial • NEXUS STORE PS4")
                    .font(.caption)
                    .foregroundStyle(NexusTheme.textSecondary)
            }

            Spacer()

            Button(action: onOpenSettings) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(service.isConnected ? NexusTheme.successGreen : NexusTheme.errorRed)
                        .frame(width: 8, height: 8)
                    Text(service.isConnected ? "Online" : "Offline")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NexusTheme.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .nexusCard(cornerRadius: 20)
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 14) {
            statCard(
                title: "Cadastrados",
                value: "\(service.games.count)",
                icon: "square.stack.3d.up.fill",
                accent: NexusTheme.electricGlow
            )
            statCard(
                title: "Publicados",
                value: "\(publishedCount)",
                icon: "checkmark.seal.fill",
                accent: NexusTheme.successGreen
            )
        }
    }

    private func statCard(title: String, value: String, icon: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(NexusTheme.textPrimary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(NexusTheme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nexusCard()
    }

    private var shortcutsSection: some View {
        VStack(spacing: 12) {
            Button(action: onNavigateToCreate) {
                HStack(spacing: 14) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Text("Cadastrar Novo Jogo")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(
                    LinearGradient(
                        colors: [NexusTheme.electricBlue, NexusTheme.electricGlow],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button(action: onNavigateToCatalog) {
                HStack(spacing: 14) {
                    Image(systemName: "books.vertical.fill")
                        .font(.title3)
                        .foregroundStyle(NexusTheme.electricGlow)
                    Text("Visualizar Catálogo")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(NexusTheme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(NexusTheme.textSecondary)
                }
                .padding(18)
                .nexusCard()
            }
        }
    }

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Últimos Jogos Adicionados")
                .font(.headline.weight(.semibold))
                .foregroundStyle(NexusTheme.textPrimary)

            if !service.config.isConfigured {
                VStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                        .font(.largeTitle)
                        .foregroundStyle(NexusTheme.textSecondary)
                    Text("Servidor Supabase não configurado")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NexusTheme.textPrimary)
                    Text("Toque no indicador Offline acima para conectar sua instância do Supabase.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(NexusTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .nexusCard()
            } else if service.games.isEmpty {
                VStack(spacing: 8) {
                    Text("Nenhum jogo cadastrado ainda")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(NexusTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .nexusCard()
            } else {
                ForEach(service.games.prefix(5)) { game in
                    HStack(spacing: 12) {
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
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NexusTheme.textPrimary)
                                .lineLimit(1)
                            Text("\(game.category) • \(game.size)")
                                .font(.caption)
                                .foregroundStyle(NexusTheme.textSecondary)
                        }

                        Spacer()

                        Text(game.published ? "Publicado" : "Rascunho")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                (game.published ? NexusTheme.successGreen : NexusTheme.warningAmber)
                                    .opacity(0.2)
                            )
                            .foregroundStyle(game.published ? NexusTheme.successGreen : NexusTheme.warningAmber)
                            .clipShape(Capsule())
                    }
                    .padding(12)
                    .nexusCard(cornerRadius: 14)
                }
            }
        }
    }
}
