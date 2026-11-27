import SwiftUI

/// Aba PS4 — descoberta real na rede local, estado da conexão e acesso às transferências.
struct PS4View: View {
    @ObservedObject var discovery: PS4ConnectionService
    @ObservedObject var transfers: TransferCoordinator
    @ObservedObject var router: AppRouter

    @State private var showManualSetup = false
    @State private var showAdvanced = false
    @State private var showTransferSettings = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                radar
                consoleCard
                actions
                if let error = errorMessage {
                    NoticeBanner(error, kind: .error)
                }
                if let message = transfers.lastError {
                    NoticeBanner(message, kind: .error)
                }
                requirementsCard
                recentConsoles
                transfersCard
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, NexusTheme.Metrics.screenPadding)
            .padding(.top, 8)
        }
        .background(NexusBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showManualSetup) {
            ManualConsoleView(discovery: discovery)
        }
        .sheet(isPresented: $showTransferSettings) {
            NexusSheetChrome {
                TransferSettingsView(transfers: transfers, preferences: NexusFileStorage.preferences)
            }
            .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $showAdvanced) {
            if let profile = primaryProfile {
                ConsoleAdvancedView(profile: profile, discovery: discovery)
            } else {
                ManualConsoleView(discovery: discovery)
            }
        }
    }

    // MARK: - Derived

    private var primaryProfile: ConsoleProfile? {
        discovery.connectedProfile ?? discovery.knownConsoles.first ?? discovery.discovered.first.map { discovery.profile(for: $0) }
    }

    private var errorMessage: String? {
        if case let .failed(message) = discovery.status { return message }
        return nil
    }

    private var searchStatusText: String {
        switch discovery.status {
        case .idle:
            return "Buscando console na rede local…"
        case .searching:
            return "Buscando console na rede local…"
        case .searchingFinished(let count):
            return count == 0 ? "Nenhum console respondeu na rede" : "\(count) console(s) encontrado(s)"
        case .connecting(let name):
            return "Conectando a \(name)…"
        case .connected:
            return "Console conectado"
        case .failed:
            return "Falha na conexão"
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            IconButton(systemName: "chevron.left", background: .clear) { router.section = .home }
            Spacer()
            Text("Conexão PS4")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            Spacer()
            IconButton(systemName: "gearshape.fill", background: .clear) {
                showAdvanced = true
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NexusTheme.Palette.stroke)
                .frame(height: 0.6)
                .offset(y: 10)
        }
    }

    private var radar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.redBright)
                Text(searchStatusText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
            }

            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .stroke(NexusTheme.Palette.red.opacity(0.22 - Double(index) * 0.045), lineWidth: 1)
                        .frame(width: 90 + CGFloat(index) * 58, height: 90 + CGFloat(index) * 58)
                }
                Circle()
                    .fill(RadialGradient(colors: [NexusTheme.Palette.red.opacity(0.22), .clear], center: .center, startRadius: 2, endRadius: 110))
                    .frame(width: 210, height: 210)
                VStack(spacing: 6) {
                    Image(systemName: "playstation.logo")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(NexusTheme.Palette.redBright)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .offset(y: -4)
                }
                if case .searching = discovery.status {
                    PulsingRing()
                }
            }
            .frame(height: 300)

            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.success)
                Text("Rede Wi-Fi: \(wifiName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(NexusTheme.Palette.surface))
            .overlay(Capsule().stroke(NexusTheme.Palette.stroke, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private var wifiName: String {
        LocalHTTPFileServer.currentWiFiAddress() ?? "rede local"
    }

    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "playstation.logo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.redBright)
                Text(primaryProfile?.name ?? "Nenhum console")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Spacer()
                if discovery.isConnected {
                    NexusBadge("CONECTADO", style: .green)
                } else if let device = discovery.discovered.first {
                    NexusBadge(device.isAwake ? "DISPONÍVEL" : "EM ESPERA", style: device.isAwake ? .green : .warning)
                } else {
                    NexusBadge("NÃO ENCONTRADO", style: .neutral)
                }
            }
            Rectangle().fill(NexusTheme.Palette.stroke).frame(height: 0.6)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    infoCell(title: "Status", value: statusValue, valueColor: discovery.isConnected ? NexusTheme.Palette.success : NexusTheme.Palette.textSecondary)
                    infoCell(title: "IP Local", value: primaryProfile?.host ?? "—")
                }
                GridRow {
                    infoCell(title: "Porta / Serviço", value: "FTP / Direct Link (Porta \(primaryProfile?.port ?? 2121))")
                    infoCell(title: "ID do Console", value: discovery.discovered.first?.hostId ?? "—")
                }
                GridRow {
                    infoCell(title: "Firmware", value: firmwareValue)
                    infoCell(title: "Espaço Livre", value: "—")
                }
            }

            NoticeBanner("Dados obtidos pela descoberta real na rede local (DDP). O envio de arquivos exige um servidor FTP ativo no console.", kind: .info)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.largeRadius, style: .continuous)
                .fill(NexusTheme.Palette.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.largeRadius, style: .continuous)
                .stroke(NexusTheme.Palette.red.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: NexusTheme.Palette.red.opacity(0.18), radius: 22, y: 10)
    }

    private var statusValue: String {
        if discovery.isConnected { return "Conectado" }
        if case .connecting = discovery.status { return "Conectando…" }
        if let device = discovery.discovered.first {
            return device.isAwake ? "Pronto para Conectar" : "Em modo de espera"
        }
        return "Desconhecido"
    }

    private var firmwareValue: String {
        // Firmware is not exposed by DDP; never invent a value.
        discovery.discovered.isEmpty ? "—" : "não informado pelo console"
    }

    private func infoCell(title: String, value: String, valueColor: Color = NexusTheme.Palette.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if discovery.isConnected, let profile = discovery.connectedProfile {
                Button {
                    discovery.disconnect()
                } label: {
                    Label("DESCONECTAR \(profile.name.uppercased())", systemImage: "bolt.slash.fill")
                }
                .buttonStyle(SecondaryActionButtonStyle())
            } else if case .searching = discovery.status {
                Button {
                    discovery.cancelScan()
                } label: {
                    Label("CANCELAR BUSCA", systemImage: "xmark")
                }
                .buttonStyle(SecondaryActionButtonStyle())
            } else if let profile = primaryProfile {
                Button {
                    discovery.connect(to: profile)
                } label: {
                    Label(connectTitle, systemImage: "link")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isConnecting)
            } else {
                Button {
                    discovery.scan()
                } label: {
                    Label("CONECTAR AO CONSOLE", systemImage: "link")
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }

            Button {
                discovery.scan()
            } label: {
                Label("BUSCAR NOVAMENTE", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(isSearching)

            Button {
                showManualSetup = true
            } label: {
                Label("CONFIGURAR MANUALMENTE", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            Text("Certifique-se de que o seu PS4 está ligado e conectado na mesma rede Wi-Fi deste iPhone.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private var connectTitle: String {
        if case let .connecting(name) = discovery.status { return "CONECTANDO A \(name.uppercased())…" }
        return "CONECTAR AO CONSOLE"
    }

    private var isConnecting: Bool {
        if case .connecting = discovery.status { return true }
        return false
    }

    private var isSearching: Bool {
        if case .searching = discovery.status { return true }
        return false
    }

    private var requirementsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Requisitos no console")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            ForEach(requirementLines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(NexusTheme.Palette.redBright)
                        .padding(.top, 6)
                    Text(line)
                        .font(.system(size: 11.5))
                        .foregroundStyle(NexusTheme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous).fill(NexusTheme.Palette.surface.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
    }

    private var requirementLines: [String] {
        [
            "PS4 ligado e na mesma rede Wi-Fi do iPhone.",
            "Um servidor FTP compatível em execução no console (ex.: 2121) para o envio de arquivos.",
            "Permissão de Rede Local concedida ao Nexus Store nos Ajustes do iOS.",
            "Enviar um .pkg não instala o jogo: a instalação depende do ambiente configurado no console."
        ]
    }

    private var recentConsoles: some View {
        Group {
            if !discovery.knownConsoles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CONSOLES RECENTES")
                        .font(NexusTheme.Typography.tiny)
                        .kerning(0.6)
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    ForEach(discovery.knownConsoles) { console in
                        HStack(spacing: 12) {
                            Image(systemName: "playstation.logo")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(NexusTheme.Palette.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(console.name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                                Text("\(console.displayAddress) • \(console.lastConnectedAt == nil ? "Desconectado" : "Conectado recentemente")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(NexusTheme.Palette.textTertiary)
                            }
                            Spacer()
                            Button {
                                discovery.connect(to: console)
                            } label: {
                                Text("Conectar")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(NexusTheme.Palette.redBright)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NexusTheme.Palette.surface.opacity(0.75)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var transfersCard: some View {
        Button {
            router.ps4Path.append(PS4Destination.transfers)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.redBright)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Central de Transferência")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    Text(transfers.activeJob.map { "\($0.gameName) • \($0.percentageText)" } ?? "Nenhuma transferência em andamento")
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
}

/// Animated ring shown while the DDP scan runs.
struct PulsingRing: View {
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(NexusTheme.Palette.red.opacity(0.5), lineWidth: 1.2)
            .frame(width: 90, height: 90)
            .scaleEffect(animate ? 3.1 : 0.7)
            .opacity(animate ? 0 : 0.9)
            .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: animate)
            .onAppear { animate = true }
    }
}
