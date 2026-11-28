import SwiftUI
import UIKit

/// Individual game page: banner, title, stats, connection status, description, metadata,
/// screenshots and the "ENVIAR PARA PS4" action.
struct GameDetailView: View {
    let gameID: UUID
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var transfers: TransferCoordinator
    @ObservedObject var discovery: PS4ConnectionService
    @ObservedObject var router: AppRouter

    @Environment(\.dismiss) private var dismiss
    @State private var showingSendOptions = false
    @State private var sendError: String?
    @State private var toast: String?

    private var game: Game? { catalog.game(id: gameID) }

    var body: some View {
        ZStack(alignment: .top) {
            NexusBackground()
            if let game {
                content(game)
            } else {
                EmptyStateView(
                    icon: "questionmark.folder",
                    title: "Jogo não encontrado",
                    message: "Este jogo foi removido do catálogo.",
                    actionTitle: "Voltar",
                    action: { dismiss() }
                )
                .padding(NexusTheme.Metrics.screenPadding)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let game { bottomBar(game) }
        }
        .sheet(isPresented: $showingSendOptions) {
            if let game {
                NexusSheetChrome {
                    SendToConsoleSheet(game: game, discovery: discovery, transfers: transfers) { message in
                        showingSendOptions = false
                        toast = message
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .alert("Não foi possível enviar", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(NexusTheme.Palette.surfaceSecondary))
                    .overlay(Capsule().stroke(NexusTheme.Palette.stroke, lineWidth: 1))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_800_000_000)
                        withAnimation { self.toast = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toast)
    }

    // MARK: - Content

    private func content(_ game: Game) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                banner(game)
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock(game)
                    statsRow(game)
                    connectionCard
                    aboutBlock(game)
                    metadataRow(game)
                    screenshots(game)
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, NexusTheme.Metrics.screenPadding)
            }
        }
    }

    private func banner(_ game: Game) -> some View {
        ZStack(alignment: .top) {
            ArtworkView(game: game, banner: true)
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .overlay(
                    LinearGradient(colors: [.clear, .black.opacity(0.15), NexusTheme.Palette.background],
                                   startPoint: .top, endPoint: .bottom)
                )
            HStack {
                IconButton(systemName: "chevron.left", background: Color.black.opacity(0.45)) { dismiss() }
                Spacer()
                IconButton(
                    systemName: catalog.isFavorite(game) ? "heart.fill" : "heart",
                    tint: catalog.isFavorite(game) ? NexusTheme.Palette.redBright : .white,
                    background: Color.black.opacity(0.45)
                ) { catalog.toggleFavorite(game) }
                IconButton(systemName: "square.and.arrow.up", background: Color.black.opacity(0.45)) {
                    UIPasteboard.general.string = game.downloadURLString
                    toast = "Link do pacote copiado"
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func titleBlock(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !game.platformTag.isEmpty {
                    NexusBadge(game.platformTag.uppercased())
                }
                if SeedCatalog.isSample(game) {
                    NexusBadge("DEMO", style: .neutral)
                }
                if game.isFeatured {
                    NexusBadge("DESTAQUE", style: .neutral)
                }
            }
            Text(game.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if game.rating > 0 {
                    RatingLabel(rating: game.rating, count: game.ratingCountText)
                    Text("•").foregroundStyle(NexusTheme.Palette.textTertiary)
                }
                Text(game.categoryLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func statsRow(_ game: Game) -> some View {
        HStack(spacing: 8) {
            StatTile(value: ByteFormatting.formatSize(game.byteCount), label: "Tamanho")
            StatTile(value: "v\(game.version.isEmpty ? "—" : game.version)", label: "Versão")
            StatTile(value: game.tags.first ?? "PT-BR", label: "Áudio & Leg.")
            StatTile(value: "1 Jogador", label: "Modo de Jogo")
        }
    }

    private var connectionCard: some View {
        Group {
            if let profile = discovery.connectedProfile, discovery.isConnected {
                HStack(spacing: 8) {
                    Circle().fill(NexusTheme.Palette.success).frame(width: 7, height: 7)
                    Text("Console conectado:")
                        .foregroundStyle(NexusTheme.Palette.textSecondary)
                    Text("\(profile.name) (\(profile.host))")
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    Spacer()
                }
                .font(.system(size: 12, weight: .medium))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
            } else {
                HStack(spacing: 8) {
                    Circle().fill(NexusTheme.Palette.textTertiary).frame(width: 7, height: 7)
                    Text("Nenhum console conectado")
                        .foregroundStyle(NexusTheme.Palette.textSecondary)
                    Spacer()
                    Button {
                        router.section = .ps4
                    } label: {
                        Text("Conectar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.redBright)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
            }
        }
    }

    private func aboutBlock(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sobre o Jogo")
                .font(NexusTheme.Typography.sectionTitle)
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            Text(game.description.isEmpty ? "Sem descrição cadastrada." : game.description)
                .font(.system(size: 14))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metadataRow(_ game: Game) -> some View {
        HStack(spacing: 8) {
            metadataTile(title: "Desenvolvedora", value: game.developer.isEmpty ? "—" : game.developer)
            metadataTile(title: "Distribuidora", value: game.publisher.isEmpty ? "—" : game.publisher)
            metadataTile(title: "Classificação", value: game.ageRating.isEmpty ? "—" : game.ageRating)
        }
    }

    private func metadataTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
    }

    private func screenshots(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capturas de Tela")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            if game.bannerURLString.isEmpty {
                Text("Nenhuma captura cadastrada para este jogo.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { index in
                            ArtworkView(reference: game.bannerArtwork, initials: ArtworkView.initials(for: game.name))
                                .frame(width: 220, height: 124)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
                                )
                                .opacity(index == 0 ? 1 : 0.85)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom bar

    private func bottomBar(_ game: Game) -> some View {
        VStack(spacing: 8) {
            Button {
                if discovery.connectedProfile != nil, discovery.isConnected {
                    startTransfer(game, to: discovery.connectedProfile!)
                } else if let console = discovery.knownConsoles.first {
                    startTransfer(game, to: console)
                } else {
                    showingSendOptions = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .bold))
                    Text("ENVIAR PARA PS4")
                        .kerning(0.6)
                    Spacer()
                    Text("(\(ByteFormatting.formatSize(game.byteCount)))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(PrimaryActionButtonStyle())

            Text(game.downloadURL == nil
                 ? "Este jogo não possui um link HTTPS válido. Atualize o cadastro no painel administrativo."
                 : "O download começa no iPhone e o envio usa o console conectado. Enviar o arquivo não instala o jogo automaticamente.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(game.downloadURL == nil ? NexusTheme.Palette.danger : NexusTheme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, NexusTheme.Metrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(NexusTheme.Palette.background.opacity(0.55))
                .overlay(alignment: .top) { Rectangle().fill(NexusTheme.Palette.stroke).frame(height: 0.6) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func startTransfer(_ game: Game, to console: ConsoleProfile) {
        if transfers.send(game: game, to: console) {
            router.section = .ps4
            router.ps4Path.append(PS4Destination.transfers)
        } else {
            sendError = transfers.lastError ?? "Falha ao iniciar a transferência."
        }
    }
}

/// Sheet that lets the user pick a console (or learn how to connect one) before sending.
struct SendToConsoleSheet: View {
    let game: Game
    @ObservedObject var discovery: PS4ConnectionService
    @ObservedObject var transfers: TransferCoordinator
    var onResult: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Enviar para o console")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Spacer()
                IconButton(systemName: "xmark", background: NexusTheme.Palette.surfaceSecondary) { dismiss() }
            }

            if discovery.knownConsoles.isEmpty {
                NoticeBanner("Nenhum console cadastrado. Vá até a aba PS4 para buscar o console na rede local.", kind: .warning)
                Button("Abrir aba PS4") { dismiss() }
                    .buttonStyle(SecondaryActionButtonStyle())
            } else {
                ForEach(discovery.knownConsoles) { console in
                    Button {
                        if transfers.send(game: game, to: console) {
                            onResult("Transferência iniciada para \(console.name)")
                        } else {
                            error = transfers.lastError
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "playstation.logo")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(NexusTheme.Palette.redBright)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(console.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                                Text(console.displayAddress)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(NexusTheme.Palette.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(NexusTheme.Palette.textTertiary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NexusTheme.Palette.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error {
                NoticeBanner(error, kind: .error)
            }

            NoticeBanner("Enviar o arquivo .pkg não instala o jogo no console. A instalação depende do servidor/ambiente configurado no PS4.", kind: .info)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(NexusTheme.Palette.backgroundElevated)
    }
}
