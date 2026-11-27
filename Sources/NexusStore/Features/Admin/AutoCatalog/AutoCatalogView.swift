import SwiftUI
import UIKit

/// Assistente IA — Auto-Catálogo (tela de configuração + parâmetros).
///
/// Implementa a referência visual: cabeçalho com subtítulo, badge de estado da API, seção de
/// configuração da chave, seção de parâmetros (categorias, quantidade, extração automática),
/// histórico e o botão principal vermelho.
struct AutoCatalogView: View {
    @ObservedObject var assistant: AutoCatalogStore
    @ObservedObject var catalog: CatalogStore

    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyInput = ""
    @State private var isKeyVisible = false
    @State private var selectedCategories: Set<String>
    @State private var quantity: Int
    @State private var extractArtwork: Bool
    @State private var showKeyHelp = false
    @State private var activeSearchID: UUID?

    init(assistant: AutoCatalogStore, catalog: CatalogStore) {
        self.assistant = assistant
        self.catalog = catalog
        let config = assistant.configuration
        _selectedCategories = State(initialValue: Set(config.defaultCategories))
        _quantity = State(initialValue: config.defaultQuantity)
        _extractArtwork = State(initialValue: config.extractArtwork)
    }

    private var isBusy: Bool {
        switch assistant.phase {
        case .testing, .searching: return true
        default: return false
        }
    }

    private var canStart: Bool {
        assistant.hasAPIKey && !selectedCategories.isEmpty && !isBusy
    }

    var body: some View {
        ZStack {
            NexusBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    subtitleBar
                    apiSection
                    parametersSection
                    promptPreview
                    startButton
                    historySection
                    legalNote
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, NexusTheme.Metrics.screenPadding)
                .padding(.top, 6)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { activeSearchID != nil },
            set: { if !$0 { activeSearchID = nil } }
        )) {
            if let id = activeSearchID {
                AutoCatalogReviewView(assistant: assistant, catalog: catalog, searchID: id)
            }
        }
        .sheet(isPresented: $showKeyHelp) { keyHelpSheet }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            IconButton(systemName: "chevron.left", background: .clear) { dismiss() }
            Spacer()
            Text("Assistente IA — Auto-Catálogo")
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
    }

    private var subtitleBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cadastro Inteligente com IA • Admin Panel")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                Spacer(minLength: 8)
                statusBadge
            }
            Rectangle()
                .fill(NexusTheme.Palette.red)
                .frame(width: 74, height: 2.5)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                .fill(NexusTheme.Palette.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch assistant.phase {
        case .connected:
            badge(text: "API CONECTADA", color: NexusTheme.Palette.success)
        case .testing, .searching:
            badge(text: "PROCESSANDO", color: NexusTheme.Palette.warning)
        case .failed:
            badge(text: "VERIFICAR", color: NexusTheme.Palette.danger)
        case .idle:
            if assistant.hasAPIKey {
                badge(text: "CHAVE SALVA", color: NexusTheme.Palette.textSecondary)
            } else {
                badge(text: "SEM CHAVE", color: NexusTheme.Palette.textTertiary)
            }
        }
    }

    private func badge(text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.4)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }

    // MARK: - API section

    private var apiSection: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(icon: "sparkles", text: "Configuração da API de IA")

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Modelo de IA")
                    Menu {
                        ForEach(AutoCatalogConfiguration.Model.allCases) { model in
                            Button {
                                assistant.selectModel(model)
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                if model == assistant.configuration.model {
                                    Label(model.title, systemImage: "checkmark")
                                } else {
                                    Text(model.title)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(assistant.configuration.model.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                                Text(assistant.configuration.model.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(NexusTheme.Palette.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NexusTheme.Palette.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(fieldBackground)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("\(assistant.configuration.model.credentialName)")
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            if isKeyVisible {
                                TextField(assistant.hasAPIKey ? "Nova chave" : "Cole sua chave", text: $apiKeyInput)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                            } else {
                                SecureField(assistant.hasAPIKey ? "Chave salva no Keychain" : "Cole sua chave", text: $apiKeyInput)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                            }

                            Button {
                                isKeyVisible.toggle()
                            } label: {
                                Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 13))
                                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                            }
                            .accessibilityLabel(isKeyVisible ? "Ocultar chave" : "Mostrar chave")
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(fieldBackground)

                        Button {
                            Task { await saveAndTest() }
                        } label: {
                            HStack(spacing: 5) {
                                if isBusy {
                                    ProgressView().tint(NexusTheme.Palette.redBright).scaleEffect(0.6)
                                }
                                Text("Testar Conexão")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundStyle(NexusTheme.Palette.redBright)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(NexusTheme.Palette.red.opacity(0.55), lineWidth: 1)
                            )
                        }
                        .disabled(isBusy)
                        .opacity(isBusy ? 0.55 : 1)
                    }
                }

                if let saved = assistant.savedKeyDescription {
                    HStack(spacing: 5) {
                        Text("Chave salva:")
                            .font(.system(size: 10.5))
                            .foregroundStyle(NexusTheme.Palette.textTertiary)
                        Text(saved)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(NexusTheme.Palette.textSecondary)
                    }
                }

                connectionRow

                if assistant.apiKeyLooksWrongForGemini {
                    NoticeBanner(
                        "Essa chave não parece ser do Google AI. As chaves do Gemini começam com AIza — gere uma em aistudio.google.com/apikey.",
                        kind: .error
                    )
                }

                if assistant.apiKeyLooksLikeGoogleKey {
                    NoticeBanner(
                        "A chave salva começa com AIza, ou seja, é do Google/Gemini. Ela não funciona na busca de metadados (RAWG). Crie a chave gratuita em rawg.io/apikey e cole acima.",
                        kind: .error
                    )
                }

                HStack(spacing: 14) {
                    Button {
                        showKeyHelp = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle")
                            Text("Por que não Gemini?")
                        }
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: assistant.configuration.model.credentialHelpURLString)!) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Obter chave")
                        }
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var connectionRow: some View {
        switch assistant.phase {
        case .connected(let milliseconds):
            HStack(spacing: 6) {
                Circle().fill(NexusTheme.Palette.success).frame(width: 6, height: 6)
                Text("Conectado • Pronto para buscar")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.success)
                Spacer()
                Text("\(milliseconds) ms")
                    .font(.system(size: 11))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
        case .failed(let message):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(NexusTheme.Palette.danger)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(NexusTheme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .searching(let step):
            HStack(spacing: 8) {
                ProgressView().tint(NexusTheme.Palette.redBright).scaleEffect(0.7)
                Text(step)
                    .font(.system(size: 11.5))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
            }
        case .testing:
            Text("Testando conexão…")
                .font(.system(size: 11.5))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
        case .idle:
            HStack(spacing: 6) {
                Circle().fill(assistant.hasAPIKey ? NexusTheme.Palette.warning : NexusTheme.Palette.textTertiary)
                    .frame(width: 6, height: 6)
                Text(assistant.hasAPIKey
                     ? "Chave salva • toque em Testar Conexão"
                     : "Informe a chave e teste a conexão")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
        }
    }

    // MARK: - Parameters

    private var parametersSection: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(icon: "magnifyingglass", text: "Parâmetros de Busca Automática")

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Categorias para Buscar")
                    FlowLayout(spacing: 8) {
                        ForEach(Self.assistantCategories) { category in
                            categoryChip(category)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Quantidade de Jogos")
                    HStack(spacing: 10) {
                        stepButton(systemName: "minus") { quantity = max(1, quantity - 1) }
                        Text(quantity == 1 ? "1 jogo" : "\(quantity) jogos")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(NexusTheme.Palette.textPrimary)
                            .frame(maxWidth: .infinity)
                        stepButton(systemName: "plus") { quantity = min(20, quantity + 1) }
                    }
                }

                Rectangle().fill(NexusTheme.Palette.stroke).frame(height: 0.8)

                Toggle(isOn: $extractArtwork) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Extrair capa, banner, tamanho e link .PKG automaticamente")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Busca metadados completos via API e atualiza o catálogo")
                            .font(.system(size: 10.5))
                            .foregroundStyle(NexusTheme.Palette.textTertiary)
                    }
                }
                .tint(NexusTheme.Palette.red)
            }
        }
    }

    private func categoryChip(_ category: GameCategory) -> some View {
        let isOn = selectedCategories.contains(category.rawValue)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if isOn {
                selectedCategories.remove(category.rawValue)
            } else {
                selectedCategories.insert(category.rawValue)
            }
        } label: {
            Text(category.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isOn ? Color.white : NexusTheme.Palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn ? NexusTheme.Palette.red : Color.clear))
                .overlay(Capsule().stroke(isOn ? Color.clear : NexusTheme.Palette.strokeStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var promptPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            Text(searchPrompt)
                .font(.system(size: 11))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(NexusTheme.Palette.surfaceSecondary.opacity(0.7))
        )
    }

    private var searchPrompt: String {
        let names = Self.assistantCategories
            .filter { selectedCategories.contains($0.rawValue) }
            .map(\.title)
        let list = names.isEmpty ? "nenhuma categoria" : names.joined(separator: ", ")
        return "Próxima consulta: buscar \(quantity) título(s) de PS4 em \(list) com metadados, capas e fontes."
    }

    // MARK: - Start

    private var startButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await start() }
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(isBusy ? "BUSCANDO…" : "INICIAR BUSCA COM IA")
                        .font(.system(size: 14, weight: .bold))
                        .kerning(0.3)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(!canStart)
            .opacity(canStart ? 1 : 0.45)

            Text("A IA buscará metadados, capas e banners de fontes reais. Links .PKG nunca são inventados: só entram se você informar uma fonte autorizada.")
                .font(.system(size: 10))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HISTÓRICO DE PESQUISAS (\(assistant.history.count))")
                    .font(NexusTheme.Typography.tiny)
                    .kerning(0.6)
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
                Spacer()
                if !assistant.history.isEmpty {
                    Button {
                        assistant.clearHistory()
                    } label: {
                        Text("Limpar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.redBright)
                    }
                    .buttonStyle(.plain)
                }
            }

            if assistant.history.isEmpty {
                Text("Nenhuma pesquisa ainda. Configure a chave e inicie a primeira busca.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface.opacity(0.5)))
            } else {
                ForEach(assistant.history.prefix(4)) { search in
                    historyRow(search)
                }
            }
        }
    }

    private func historyRow(_ search: AutoCatalogSearch) -> some View {
        Button {
            activeSearchID = search.id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.dateFormatter.string(from: search.startedAt))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                    Text(historySummary(search))
                        .font(.system(size: 10.5))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if search.errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(NexusTheme.Palette.danger)
                } else {
                    Text("\(search.approvedCount)/\(search.foundCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.success)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Repetir pesquisa") { Task { await repeatSearch(search) } }
            Button("Excluir do histórico", role: .destructive) { assistant.delete(searchID: search.id) }
        }
    }

    private func historySummary(_ search: AutoCatalogSearch) -> String {
        if let error = search.errorMessage { return "Falhou • \(error)" }
        let categories = search.request.categories
            .map { GameCategory.title(for: $0) }
            .joined(separator: ", ")
        return "\(search.request.quantity)x • \(categories.isEmpty ? "todas" : categories) • \(search.foundCount) encontrados"
    }

    private var legalNote: some View {
        VStack(spacing: 6) {
            // RAWG requires an active hyperlink wherever its data is displayed.
            Link(destination: URL(string: sourceCredits.url)!) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text(sourceCredits.text)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.redBright)
            }
            Text("A Nexus Store não distribui jogos: cadastre apenas arquivos que você tem direito de usar.")
                .font(.system(size: 9.5))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Help sheet

    private var keyHelpSheet: some View {
        NexusSheetChrome {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Chave de API e modelo de IA")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)

                    helpBlock(
                        title: "RAWG — banco de dados de jogos",
                        text: "Devolve campos estruturados (título, capa, gêneros, publisher) e uma página de origem para conferência. Gratuita para uso pessoal, exige atribuição com link. Não informa tamanho de pacote .pkg: esse campo fica vazio e é você quem preenche."
                    )
                    helpBlock(
                        title: "Gemini + Pesquisa Google",
                        text: "O Gemini sozinho responde de memória. Com a ferramenta google_search ele pesquisa de verdade, e o app só aceita um jogo quando o Google devolve uma citação para ele. Tamanho de pacote só é mantido se vier citado de uma fonte; caso contrário fica vazio. Nada de link .pkg é gerado pela IA."
                    )
                    helpBlock(
                        title: "Onde pego cada chave",
                        text: "RAWG: rawg.io/apikey (grátis). Gemini: aistudio.google.com/apikey (chave começa com AIza). As duas ficam em itens separados do Keychain, então você pode alternar entre elas sem digitar de novo."
                    )
                    helpBlock(
                        title: "Onde a chave fica guardada",
                        text: "No Keychain do iPhone, com acesso após o primeiro desbloqueio e somente neste aparelho. Ela não é enviada a nenhum servidor além da própria RAWG, não aparece em logs e não está no repositório."
                    )
                    Button("Entendi") { showKeyHelp = false }
                        .buttonStyle(PrimaryActionButtonStyle())
                }
                .padding(20)
            }
        }
        .presentationDetents([.large])
    }

    private func helpBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.redBright)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Attribution for the active provider (RAWG requires a link; Gemini grounding requires
    /// the "Search" label on results).
    private var sourceCredits: (text: String, url: String) {
        switch assistant.configuration.model {
        case .rawg:
            return ("Dados e imagens: RAWG Video Games Database", "https://rawg.io")
        case .gemini:
            return ("Resultados com Google Search (Gemini)", "https://ai.google.dev/gemini-api/docs/google-search")
        }
    }

    // MARK: - Actions

    private func saveAndTest() async {
        if !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assistant.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
        }
        await assistant.testConnection()
        UINotificationFeedbackGenerator().notificationOccurred(
            assistant.phase.isConnected ? .success : .error
        )
    }

    private func start() async {
        assistant.saveConfiguration(AutoCatalogConfiguration(
            model: assistant.configuration.model,
            defaultCategories: Array(selectedCategories),
            defaultQuantity: quantity,
            extractArtwork: extractArtwork,
            verifyPKGLinks: assistant.configuration.verifyPKGLinks
        ))
        let request = AutoCatalogRequest(
            categories: Array(selectedCategories),
            quantity: quantity,
            extractArtwork: extractArtwork
        )
        guard let record = await assistant.startSearch(request: request) else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard record.errorMessage == nil else {
            // The failure is already shown in the connection row; opening an empty "review" screen
            // would look like "no games found", which is a different (and misleading) message.
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        activeSearchID = record.id
    }

    private func repeatSearch(_ search: AutoCatalogSearch) async {
        guard let result = await assistant.startSearch(request: search.request), result.errorMessage == nil else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        activeSearchID = result.id
    }

    // MARK: - Building blocks

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(NexusTheme.Palette.surfaceSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
            )
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                    .fill(NexusTheme.Palette.surface.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                    .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
            )
    }

    private func cardTitle(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NexusTheme.Palette.textSecondary)
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .frame(width: 38, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NexusTheme.Palette.surfaceSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    static let assistantCategories: [GameCategory] = GameCategory.all

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM 'às' HH:mm"
        return formatter
    }()
}

private extension AutoCatalogStore.Phase {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
