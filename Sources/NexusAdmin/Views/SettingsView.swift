import SwiftUI

struct SettingsView: View {
    @ObservedObject var service: SupabaseService
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput: String = ""
    @State private var anonKeyInput: String = ""
    @State private var tokenInput: String = ""
    @State private var statusMessage: String?
    @State private var isTesting: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("NEXUS CLOUD (Supabase)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(NexusTheme.textPrimary)

                        Text("Nenhuma chave secreta é armazenada no código do aplicativo. Insira as credenciais do seu projeto Supabase abaixo.")
                            .font(.caption)
                            .foregroundStyle(NexusTheme.textSecondary)

                        field(title: "Project URL", placeholder: "https://seu-projeto.supabase.co", text: $urlInput)
                        field(title: "Anon / Public Key", placeholder: "eyJhbGciOi...", text: $anonKeyInput)
                        field(title: "Access Token (opcional / sessão)", placeholder: "Bearer token autenticado", text: $tokenInput)
                    }
                    .padding(16)
                    .nexusCard()

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(service.isConnected ? NexusTheme.successGreen : NexusTheme.warningAmber)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .nexusCard(cornerRadius: 12)
                    }

                    Button {
                        Task { await saveAndTest() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView().tint(.white)
                            }
                            Text(isTesting ? "Conectando..." : "Salvar e Testar Conexão")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(NexusTheme.electricBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(isTesting)
                }
                .padding(18)
            }
            .background(NexusTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Conexão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(NexusTheme.electricGlow)
                }
            }
            .onAppear {
                urlInput = service.config.projectURL
                anonKeyInput = service.config.anonKey
                tokenInput = service.config.accessToken
            }
        }
    }

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NexusTheme.textSecondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .foregroundStyle(NexusTheme.textPrimary)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func saveAndTest() async {
        isTesting = true
        defer { isTesting = false }

        service.config = SupabaseConfig(
            projectURL: urlInput,
            anonKey: anonKeyInput,
            accessToken: tokenInput
        )
        let ok = await service.testConnection()
        if ok {
            await service.fetchGames()
            statusMessage = "Conectado ao Supabase com sucesso!"
        } else {
            statusMessage = "Não foi possível conectar. Verifique a URL, a chave e a tabela 'games'."
        }
    }
}
