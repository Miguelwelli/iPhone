import SwiftUI
import UIKit

/// Manual console configuration — required whenever DDP discovery is blocked (guest Wi-Fi, standby,
/// no FTP server). Every field is validated before saving, and the test is a real FTP login.
struct ManualConsoleView: View {
    @ObservedObject var discovery: PS4ConnectionService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var host = ""
    @State private var portText = "2121"
    @State private var username = "anonymous"
    @State private var remotePath = "/"
    @State private var method: SendingMethod = .ftp
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var testing = false

    private var draftProfile: ConsoleProfile {
        ConsoleProfile(
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "PS4" : name,
            host: host.trimmingCharacters(in: .whitespaces),
            port: UInt16(portText) ?? 0,
            username: username,
            remotePath: remotePath,
            isManual: true,
            preferredMethod: method
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configurar console")
                    .font(NexusTheme.Typography.screenTitle)
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Text("Informe o IP do PS4 mostrado em Ajustes → Rede → Status da conexão.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)

                field("Nome do console", text: $name, placeholder: "PS4 PRO - SALA")
                field("Endereço IP", text: $host, placeholder: "192.168.1.104", keyboard: .numbersAndPunctuation)
                field("Porta FTP", text: $portText, placeholder: "2121", keyboard: .numberPad)
                field("Usuário FTP", text: $username, placeholder: "anonymous")
                field("Caminho remoto", text: $remotePath, placeholder: "/")

                VStack(alignment: .leading, spacing: 8) {
                    Text("MÉTODO DE ENVIO")
                        .font(NexusTheme.Typography.tiny)
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    ForEach(SendingMethod.allCases) { option in
                        Button {
                            method = option
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: method == option ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(method == option ? NexusTheme.Palette.redBright : NexusTheme.Palette.textTertiary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                                    Text(option.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface.opacity(method == option ? 1 : 0.55)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(method == option ? NexusTheme.Palette.red.opacity(0.55) : NexusTheme.Palette.stroke, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorMessage {
                    NoticeBanner(errorMessage, kind: .error)
                }
                if let savedMessage {
                    NoticeBanner(savedMessage, kind: .success)
                }

                Button {
                    saveAndTest()
                } label: {
                    if testing {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("TESTANDO CONEXÃO…")
                        }
                    } else {
                        Label("SALVAR E TESTAR FTP", systemImage: "bolt.horizontal.circle.fill")
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(testing)

                Button("Salvar sem testar") { save(showConfirmation: true) }
                    .buttonStyle(SecondaryActionButtonStyle())

                NoticeBanner("O teste abre uma conexão FTP real com o console e confirma o login. Sem um servidor FTP ativo no PS4, o teste falhará — isso não é um erro do aplicativo.", kind: .info)
                Color.clear.frame(height: 12)
            }
            .padding(NexusTheme.Metrics.screenPadding)
        }
        .background(NexusBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let existing = discovery.knownConsoles.first {
                name = existing.name
                host = existing.host
                portText = String(existing.port)
                username = existing.username
                remotePath = existing.remotePath
                method = existing.preferredMethod
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
        }
    }

    private func saveAndTest() {
        guard save(showConfirmation: false) else { return }
        testing = true
        errorMessage = nil
        discovery.connect(to: draftProfile)
        // Observe the service result for a few seconds without blocking the UI.
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if case let .failed(message) = discovery.status {
                    errorMessage = message
                    testing = false
                    return
                }
                if discovery.isConnected {
                    savedMessage = "Conexão FTP estabelecida com \(draftProfile.name)."
                    testing = false
                    return
                }
            }
            testing = false
            errorMessage = "Tempo esgotado ao testar a conexão FTP."
        }
    }

    @discardableResult
    private func save(showConfirmation: Bool) -> Bool {
        let profile = draftProfile
        if let error = profile.validationError() {
            errorMessage = error
            return false
        }
        discovery.save(profile)
        if showConfirmation {
            savedMessage = "Console salvo."
            errorMessage = nil
        }
        return true
    }
}

/// Advanced options for a console: change method, delete, open the transfer center.
struct ConsoleAdvancedView: View {
    let profile: ConsoleProfile
    @ObservedObject var discovery: PS4ConnectionService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ajustes do console")
                    .font(NexusTheme.Typography.screenTitle)
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Nome", profile.name)
                    detailRow("Endereço", profile.displayAddress)
                    detailRow("Usuário FTP", profile.username)
                    detailRow("Caminho remoto", profile.remotePath)
                    detailRow("Método preferido", profile.preferredMethod.title)
                    detailRow("Origem", profile.isManual ? "Configuração manual" : "Descoberta automática (DDP)")
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NexusTheme.Palette.surface))

                if let error = profile.validationError() {
                    NoticeBanner(error, kind: .warning)
                }

                Button("Desconectar") {
                    discovery.disconnect()
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button(role: .destructive) {
                    discovery.delete(profile)
                    dismiss()
                } label: {
                    Label("Remover console", systemImage: "trash")
                }
                .buttonStyle(SecondaryActionButtonStyle())

                NoticeBanner("Remover o console apaga apenas o cadastro local no iPhone; nada é alterado no PS4.", kind: .info)
            }
            .padding(NexusTheme.Metrics.screenPadding)
        }
        .background(NexusBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
        }
    }
}
