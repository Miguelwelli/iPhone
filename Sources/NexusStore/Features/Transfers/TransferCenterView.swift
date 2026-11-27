import SwiftUI

/// Central de Transferência — capa, nome, porcentagem real, barra, velocidade, tamanho enviado,
/// estado atual e console de destino. Todos os valores vêm do `TransferEngine`.
struct TransferCenterView: View {
    @ObservedObject var transfers: TransferCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCancelConfirmation = false
    @State private var showSettings = false
    @State private var showBackgroundWarning = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let job = transfers.activeJob {
                    activeCard(job)
                } else {
                    EmptyStateView(
                        icon: "arrow.up.arrow.down",
                        title: "Nenhuma transferência ativa",
                        message: "Abra um jogo e toque em ENVIAR PARA PS4 para iniciar.",
                        actionTitle: nil,
                        action: nil
                    )
                }
                if let error = transfers.lastError, transfers.activeJob == nil {
                    NoticeBanner(error, kind: .error)
                }
                historySection
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, NexusTheme.Metrics.screenPadding)
            .padding(.top, 8)
        }
        .background(NexusBackground())
        .toolbar(.hidden, for: .navigationBar)
        .alert("Transferência pode ser interrompida", isPresented: $showBackgroundWarning) {
            Button("Entendi", role: .cancel) {}
        } message: {
            Text("O iOS suspende o aplicativo em segundo plano e a conexão FTP é encerrada. Mantenha a Nexus Store aberta até a conclusão.")
        }
        .onChange(of: scenePhase) { phase in
            // Honest warning: the FTP socket cannot survive app suspension, so say so before it happens.
            if phase != .active, transfers.activeJob?.state.isRunning == true {
                showBackgroundWarning = true
            }
        }
        .sheet(isPresented: $showSettings) {
            NexusSheetChrome {
                TransferSettingsView(transfers: transfers, preferences: NexusFileStorage.preferences)
            }
            .presentationDetents([.large])
        }
        .confirmationDialog("Cancelar transferência?", isPresented: $showCancelConfirmation, titleVisibility: .visible) {
            Button("Cancelar transferência", role: .destructive) {
                if let job = transfers.activeJob { transfers.cancel(job) }
            }
            Button("Continuar", role: .cancel) {}
        } message: {
            Text("O arquivo parcial será removido do iPhone. Nada será apagado do console.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconButton(systemName: "chevron.left", background: .clear) { dismiss() }
            Spacer()
            Text("Central de Transferência")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            Spacer()
            IconButton(systemName: "gearshape", background: .clear) { showSettings = true }
                .accessibilityLabel("Ajustes de transferência")
        }
    }

    private func activeCard(_ job: TransferJob) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(job.state == .failed ? NexusTheme.Palette.danger : NexusTheme.Palette.redBright)
                    .frame(width: 7, height: 7)
                Text("Enviando para")
                    .font(.system(size: 12))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                Text(job.consoleName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Text("•").foregroundStyle(NexusTheme.Palette.textTertiary)
                Text(job.consoleHost)
                    .font(.system(size: 12))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))

            ArtworkView(reference: ArtworkReference(rawValue: job.coverURLString), initials: ArtworkView.initials(for: job.gameName))
                .frame(width: 150, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 10)

            VStack(spacing: 2) {
                Text(job.gameName)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Tamanho total: \(ByteFormatting.formatSize(job.expectedTotalBytes))")
                    .font(.system(size: 12))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }

            progressRow(job)

            HStack(spacing: 10) {
                metricTile(value: "\(ByteFormatting.formatSize(job.uploadedBytes > 0 ? job.uploadedBytes : job.downloadedBytes)) / \(ByteFormatting.formatSize(job.expectedTotalBytes))", label: job.uploadedBytes > 0 ? "Enviado" : "Baixado")
                metricTile(value: transfers.speed > 0 ? ByteFormatting.formatSpeed(transfers.speed) : "—", label: "Velocidade")
            }
            HStack(spacing: 10) {
                metricTile(value: ByteFormatting.formatRemaining(seconds: transfers.remainingSeconds), label: "Tempo restante")
                metricTile(value: job.message.isEmpty ? job.state.title : job.message, label: "Status")
            }

            HStack(spacing: 10) {
                if job.state == .downloading {
                    Button {
                        transfers.pause()
                    } label: {
                        Label("PAUSAR TRANSFERÊNCIA", systemImage: "pause.fill")
                    }
                    .buttonStyle(OutlinedDangerButtonStyle())
                } else if job.state == .paused {
                    Button {
                        transfers.resume(job)
                    } label: {
                        Label("RETOMAR", systemImage: "play.fill")
                    }
                    .buttonStyle(OutlinedDangerButtonStyle())
                } else if job.state.isRunning {
                    Button {
                        showCancelConfirmation = true
                    } label: {
                        Label("CANCELAR", systemImage: "xmark.circle")
                    }
                    .buttonStyle(OutlinedDangerButtonStyle())
                }
            }

            if transfers.speed > 0 || job.uploadedBytes > 0 {
                NoticeBanner(job.state == .transferring
                             ? "Enviando pelo FTP passivo. Não feche este app enquanto a transferência estiver em andamento."
                             : "Baixando o pacote para o iPhone. O envio ao console começa em seguida.",
                             kind: .info)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.largeRadius, style: .continuous)
                .fill(NexusTheme.Palette.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.largeRadius, style: .continuous)
                .stroke(NexusTheme.Palette.strokeStrong, lineWidth: 1)
        )
    }

    private func progressRow(_ job: TransferJob) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(job.progress, 0.02))
                    .stroke(NexusTheme.Palette.redGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: job.progress)
                VStack(spacing: 1) {
                    Text(job.percentageText)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                }
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(NexusTheme.Palette.redGradient)
                            .frame(width: max(6, geometry.size.width * job.progress))
                            .animation(.easeInOut(duration: 0.4), value: job.progress)
                    }
                }
                .frame(height: 10)
                HStack(spacing: 6) {
                    Circle()
                        .fill(job.state == .failed ? NexusTheme.Palette.danger : NexusTheme.Palette.redBright)
                        .frame(width: 6, height: 6)
                    Text(job.state == .failed ? "ERRO" : job.state.title)
                        .font(.system(size: 10.5, weight: .bold))
                        .kerning(0.4)
                        .foregroundStyle(NexusTheme.Palette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(NexusTheme.Palette.surfaceSecondary))
                    if job.state == .failed {
                        Text(job.message)
                            .font(.system(size: 10))
                            .foregroundStyle(NexusTheme.Palette.danger)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func metricTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !transfers.history.isEmpty {
                HStack {
                    Text("HISTÓRICO")
                        .font(NexusTheme.Typography.tiny)
                        .kerning(0.6)
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    Spacer()
                    Button {
                        transfers.clearHistory()
                    } label: {
                        Text("Limpar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.redBright)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(transfers.history) { job in
                    HStack(spacing: 12) {
                        ArtworkView(reference: ArtworkReference(rawValue: job.coverURLString), initials: ArtworkView.initials(for: job.gameName))
                            .frame(width: 38, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.gameName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NexusTheme.Palette.textPrimary)
                                .lineLimit(1)
                            Text(job.state == .completed
                                 ? "Concluído • \(ByteFormatting.formatSize(job.uploadedBytes))"
                                 : job.message)
                                .font(.system(size: 10.5))
                                .foregroundStyle(job.state == .completed ? NexusTheme.Palette.success : NexusTheme.Palette.danger)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            transfers.remove(job)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NexusTheme.Palette.textTertiary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface.opacity(0.7)))
                }
            }
        }
    }
}

/// Outlined red button used for pause/cancel actions.
struct OutlinedDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .bold))
            .kerning(0.3)
            .foregroundStyle(NexusTheme.Palette.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NexusTheme.Palette.red.opacity(configuration.isPressed ? 0.18 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(NexusTheme.Palette.red.opacity(0.5), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
