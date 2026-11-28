import SwiftUI
import UIKit

/// Transfer preferences (temporary files, verification) and a diagnostic panel with honest numbers.
struct TransferSettingsView: View {
    @ObservedObject var transfers: TransferCoordinator
    let preferences: PreferencesStore

    @Environment(\.dismiss) private var dismiss
    @State private var configuration = TransferConfiguration()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Ajustes de transferência")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    Spacer()
                    IconButton(systemName: "xmark", background: NexusTheme.Palette.surfaceSecondary) { dismiss() }
                }

                Toggle(isOn: $configuration.deleteLocalFileWhenDone) {
                    settingLabel("Apagar o .pkg após o envio", detail: "Libera espaço no iPhone quando o console confirma o recebimento.")
                }
                .tint(NexusTheme.Palette.red)

                Toggle(isOn: $configuration.cleanTemporaryFilesOnCancel) {
                    settingLabel("Apagar arquivos parciais ao cancelar", detail: "Remove downloads incompletos do armazenamento do app.")
                }
                .tint(NexusTheme.Palette.red)

                Toggle(isOn: $configuration.verifyRemoteSizeWhenAvailable) {
                    settingLabel("Verificar tamanho no console (SIZE)", detail: "Quando o servidor FTP informa o tamanho, o app compara com o total enviado.")
                }
                .tint(NexusTheme.Palette.red)

                Button {
                    preferences.update { $0.transferConfiguration = configuration }
                    transfers.updateConfiguration(configuration)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } label: {
                    Text("SALVAR AJUSTES").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())

                diagnostics

                NoticeBanner("Alterações afetam as próximas transferências. A transferência em andamento mantém as regras com que começou.", kind: .info)
            }
            .padding(20)
        }
        .background(NexusTheme.Palette.backgroundElevated.ignoresSafeArea())
        .onAppear { configuration = preferences.value.transferConfiguration }
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ARMAZENAMENTO")
                .font(NexusTheme.Typography.tiny)
                .kerning(0.6)
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            diagnosticRow("Espaço livre no iPhone", ByteFormatting.formatSize(NexusFileStorage.freeDiskSpace()))
            diagnosticRow("Transferências na sessão", "\(transfers.jobs.count)")
            diagnosticRow("Fila", "\(transfers.queuedJobs.count)")
            diagnosticRow("Motor", transfers.phase.title)
            Button {
                transfers.clearHistory()
            } label: {
                Text("Limpar histórico e temporários")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.redBright)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NexusTheme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
        }
    }
}
