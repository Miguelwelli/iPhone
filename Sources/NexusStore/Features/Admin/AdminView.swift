import SwiftUI
import UIKit

/// Painel Administrativo — protegido por senha, com cadastro/edição/exclusão de jogos.
/// Todos os dados são locais (JSON no iPhone); nada depende de servidor pago.
struct AdminView: View {
    @ObservedObject var catalog: CatalogStore
    let preferences: PreferencesStore
    @ObservedObject var session: AdminSession
    /// Passed down so the admin panel can open the transfer settings screen.
    @ObservedObject var transfers: TransferCoordinator

    @EnvironmentObject private var autoCatalog: AutoCatalogStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft = GameDraft()
    @State private var errors: [GameField: String] = [:]
    @State private var editing: Game?
    @State private var pendingDelete: Game?
    @State private var toast: String?
    @State private var showAllGames = false
    @State private var showChangePassword = false
    @State private var showAdminPasswordSheet = false
    @State private var showAutoCatalog = false
    @State private var showTransferSettings = false

    private var isUnlocked: Bool { session.isUnlocked && preferences.value.hasAdminPassword }

    var body: some View {
        ZStack {
            NexusBackground()
            if !preferences.value.hasAdminPassword {
                AdminPasswordSetupView(preferences: preferences, session: session)
            } else if !session.isUnlocked {
                AdminLoginView(preferences: preferences, session: session)
            } else {
                panel
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(NexusTheme.Palette.surfaceSecondary))
                    .overlay(Capsule().stroke(NexusTheme.Palette.stroke, lineWidth: 1))
                    .padding(.top, 8)
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation { self.toast = nil }
                    }
            }
        }
        .alert("Excluir jogo?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { game in
            Button("Excluir", role: .destructive) {
                if catalog.delete(game) {
                    toast = "“\(game.name)” removido do catálogo"
                    if editing?.id == game.id { resetForm() }
                }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: { game in
            Text("“\(game.name)” será removido do catálogo neste iPhone. Esta ação não afeta o console.")
        }
    }

    // MARK: - Panel

    private var panel: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                NoticeBanner("Catálogo local • \(catalog.games.count) jogos • todos os dados ficam neste iPhone", kind: .info)
                autoCatalogEntry
                formCard
                if !errors.isEmpty {
                    NoticeBanner(errors.values.sorted().joined(separator: "\n"), kind: .error)
                }
                registeredSection
                Text("Você é responsável pelo conteúdo e pelos direitos dos arquivos cadastrados.")
                    .font(.system(size: 10))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
                    .padding(.top, 4)
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, NexusTheme.Metrics.screenPadding)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showAllGames) {
            NexusSheetChrome {
                AdminGameListSheet(catalog: catalog, onEdit: { game in
                    showAllGames = false
                    startEditing(game)
                }, onDelete: { game in
                    pendingDelete = game
                })
            }
            .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $showAutoCatalog) {
            AutoCatalogView(assistant: autoCatalog, catalog: catalog)
        }
        .sheet(isPresented: $showTransferSettings) {
            NexusSheetChrome {
                TransferSettingsView(transfers: transfers, preferences: preferences)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showChangePassword) {
            NexusSheetChrome {
                ChangePasswordView(preferences: preferences, onDone: { toast = "Senha atualizada" })
            }
            .presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconButton(systemName: "chevron.left", background: .clear) { dismiss() }
            Spacer()
            VStack(spacing: 1) {
                Text("Painel Administrativo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Text("Gerenciar catálogo de jogos")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
            Spacer()
            IconButton(systemName: "gearshape.fill", background: .clear) { showTransferSettings = true }
                .accessibilityLabel("Ajustes de transferência")
            IconButton(systemName: "key.fill", background: .clear) { showChangePassword = true }
                .accessibilityLabel("Alterar senha")
            IconButton(systemName: "rectangle.portrait.and.arrow.right", background: .clear) {
                session.isUnlocked = false
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NexusTheme.Palette.surface.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editing == nil ? "CADASTRAR NOVO JOGO" : "EDITAR JOGO")
                    .font(.system(size: 13, weight: .bold))
                    .kerning(0.4)
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Rectangle().fill(NexusTheme.Palette.red).frame(width: 26, height: 2)
                Spacer()
                NexusBadge("MODO ADMIN", style: .neutral)
            }

            if editing != nil {
                HStack(spacing: 8) {
                    NexusBadge("EDITANDO", style: .warning)
                    Text(editing?.name ?? "")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        resetForm()
                    } label: {
                        Text("Cancelar")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.redBright)
                    }
                    .buttonStyle(.plain)
                }
            }

            textField("Nome do Jogo", text: $draft.name, error: errors[.name])
            categoryPicker
            HStack(spacing: 10) {
                textField("Versão", text: $draft.version, error: errors[.version])
                textField("Tamanho (GB)", text: $draft.sizeText, error: errors[.size], keyboard: .numbersAndPunctuation)
            }
            HStack(spacing: 10) {
                textField("Desenvolvedora", text: $draft.developer, error: nil)
                textField("Distribuidora", text: $draft.publisher, error: nil)
            }
            HStack(spacing: 10) {
                textField("Classificação", text: $draft.ageRating, error: nil)
                textField("Plataforma", text: $draft.platformTag, error: nil)
            }
            textField("Link do Arquivo (.pkg)", text: $draft.downloadURLString, error: errors[.downloadURL], keyboard: .URL)
            descriptionField
            HStack(spacing: 10) {
                imageField("Capa do Jogo (2:3)", text: $draft.coverURLString, error: errors[.cover], aspect: NexusTheme.Metrics.coverRatio)
                imageField("Banner de Destaque (16:9)", text: $draft.bannerURLString, error: errors[.banner], aspect: NexusTheme.Metrics.bannerRatio)
            }
            HStack(spacing: 10) {
                textField("Atributos (separados por vírgula)", text: $draft.tagsText, error: nil)
                VStack(alignment: .leading, spacing: 4) {
                    Text(" Destaque")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    Toggle("", isOn: $draft.isFeatured)
                        .labelsHidden()
                        .tint(NexusTheme.Palette.red)
                        .frame(height: 44)
                }
            }

            Button {
                submit()
            } label: {
                Label(editing == nil ? "CADASTRAR JOGO NO CATÁLOGO" : "SALVAR ALTERAÇÕES", systemImage: editing == nil ? "plus" : "checkmark")
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous).fill(NexusTheme.Palette.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Categoria")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            Menu {
                ForEach(GameCategory.all) { category in
                    Button {
                        if let index = draft.categories.firstIndex(of: category.rawValue) {
                            draft.categories.remove(at: index)
                        } else {
                            draft.categories.append(category.rawValue)
                        }
                    } label: {
                        if draft.categories.contains(category.rawValue) {
                            Label(category.title, systemImage: "checkmark")
                        } else {
                            Text(category.title)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(draft.categories.isEmpty ? "Selecionar categoria" : draft.categories.map { GameCategory.title(for: $0) }.joined(separator: " / "))
                        .font(.system(size: 14))
                        .foregroundStyle(draft.categories.isEmpty ? NexusTheme.Palette.textTertiary : NexusTheme.Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surfaceSecondary))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(errors[.categories] != nil ? NexusTheme.Palette.danger : NexusTheme.Palette.stroke, lineWidth: 1)
                )
            }
            if draft.categories.isEmpty {
                Text("Selecione ao menos uma categoria — toque para escolher.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Descrição do Jogo")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            TextEditor(text: $draft.description)
                .font(.system(size: 13))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 92)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surfaceSecondary))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
        }
    }

    private func textField(_ title: String, text: Binding<String>, error: String?, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(error == nil ? NexusTheme.Palette.textTertiary : NexusTheme.Palette.danger)
            TextField("", text: text)
                .font(.system(size: 14))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboard == .URL ? .never : .words)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surfaceSecondary))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(error == nil ? NexusTheme.Palette.stroke : NexusTheme.Palette.danger, lineWidth: 1)
                )
            if let error {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(NexusTheme.Palette.danger)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func imageField(_ title: String, text: Binding<String>, error: String?, aspect: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            HStack(spacing: 8) {
                ArtworkView(reference: ArtworkReference(rawValue: text.wrappedValue), initials: "NS")
                    .frame(width: 54, height: 54 / aspect)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
                VStack(spacing: 4) {
                    TextField("https://…", text: text)
                        .font(.system(size: 11))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NexusTheme.Palette.surfaceSecondary))
                    Text("Link HTTPS de imagem")
                        .font(.system(size: 9))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                }
            }
            if let error {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(NexusTheme.Palette.danger)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Entry point for the AI assistant: a designed card, not a generic row.
    private var autoCatalogEntry: some View {
        Button {
            showAutoCatalog = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [NexusTheme.Palette.red, NexusTheme.Palette.redDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Assistente IA — Auto-Catálogo")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(NexusTheme.Palette.textPrimary)
                        Text("NOVO")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(NexusTheme.Palette.red))
                    }
                    Text("Busque jogos de PS4, extraia metadados reais e aprove em lote")
                        .font(.system(size: 10.5))
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                    .fill(NexusTheme.Palette.surface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                    .stroke(NexusTheme.Palette.red.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var registeredSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Jogos Cadastrados (\(catalog.games.count))", actionTitle: "Ver todos") {
                showAllGames = true
            }
            if catalog.games.isEmpty {
                EmptyStateView(icon: "tray", title: "Nenhum jogo", message: "Cadastre o primeiro jogo usando o formulário acima.")
            } else {
                VStack(spacing: 0) {
                    ForEach(catalog.games.prefix(3)) { game in
                        AdminGameRow(
                            game: game,
                            onEdit: { startEditing(game) },
                            onDelete: { pendingDelete = game }
                        )
                        if game.id != catalog.games.prefix(3).last?.id {
                            Rectangle().fill(NexusTheme.Palette.stroke).frame(height: 0.6)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous).fill(NexusTheme.Palette.surface.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
            }
        }
    }

    // MARK: - Actions

    private func submit() {
        errors = draft.validate()
        guard errors.isEmpty else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        if let editing {
            switch catalog.update(draft, existing: editing) {
            case .success(let game):
                toast = "“\(game.name)” atualizado"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                resetForm()
            case .failure(let error):
                errors[.name] = error.errorDescription
            }
        } else {
            switch catalog.add(draft) {
            case .success(let game):
                toast = "“\(game.name)” adicionado ao catálogo"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                resetForm()
            case .failure(let error):
                errors[.name] = error.errorDescription
            }
        }
    }

    private func startEditing(_ game: Game) {
        editing = game
        draft = GameDraft(game: game)
        errors = [:]
    }

    private func resetForm() {
        editing = nil
        draft = GameDraft()
        errors = [:]
    }
}

// MARK: - Authentication views

struct AdminPasswordSetupView: View {
    let preferences: PreferencesStore
    @ObservedObject var session: AdminSession
    /// Passed down so the admin panel can open the transfer settings screen.
    @ObservedObject var transfers: TransferCoordinator

    @EnvironmentObject private var autoCatalog: AutoCatalogStore

    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(NexusTheme.Palette.redBright)
                .padding(.top, 60)
            Text("Proteja o painel")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            Text("Crie uma senha para o painel administrativo. Ela fica salva neste iPhone como hash com salt — a senha em si nunca é armazenada.")
                .font(.system(size: 12.5))
                .foregroundStyle(NexusTheme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            SecureField("Senha (mínimo 4 caracteres)", text: $password)
                .textContentType(.newPassword)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
            SecureField("Confirmar senha", text: $confirmation)
                .textContentType(.newPassword)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))

            if let error {
                NoticeBanner(error, kind: .error)
            }

            Button {
                createPassword()
            } label: {
                Label("CRIAR SENHA", systemImage: "checkmark.shield.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .padding(.top, 4)
            Spacer()
        }
        .padding(NexusTheme.Metrics.screenPadding)
    }

    private func createPassword() {
        if let message = AdminCredential.validate(password: password) {
            error = message
            return
        }
        guard password == confirmation else {
            error = "As senhas não coincidem."
            return
        }
        let salt = AdminCredential.makeSalt()
        let hash = AdminCredential.hash(password: password, salt: salt)
        preferences.update {
            $0.adminPasswordSalt = salt
            $0.adminPasswordHash = hash
        }
        session.isUnlocked = true
        error = nil
    }
}

struct AdminLoginView: View {
    let preferences: PreferencesStore
    @ObservedObject var session: AdminSession
    /// Passed down so the admin panel can open the transfer settings screen.
    @ObservedObject var transfers: TransferCoordinator

    @EnvironmentObject private var autoCatalog: AutoCatalogStore

    @State private var password = ""
    @State private var error: String?
    @State private var attempts = 0

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NexusTheme.Palette.redBright)
                .padding(.top, 80)
            Text("Painel Administrativo")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            Text("Informe a senha criada neste iPhone.")
                .font(.system(size: 12.5))
                .foregroundStyle(NexusTheme.Palette.textSecondary)

            SecureField("Senha", text: $password)
                .textContentType(.password)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
                .onSubmit(unlock)

            if let error {
                NoticeBanner(error, kind: .error)
            }

            Button {
                unlock()
            } label: {
                Label("DESBLOQUEAR", systemImage: "lock.open.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())

            Text("Se você esqueceu a senha, é possível redefini-la apagando os dados do app nos Ajustes do iOS. O catálogo cadastrado será perdido.")
                .font(.system(size: 10))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Spacer()
        }
        .padding(NexusTheme.Metrics.screenPadding)
    }

    private func unlock() {
        let hash = AdminCredential.hash(password: password, salt: preferences.value.adminPasswordSalt)
        if hash == preferences.value.adminPasswordHash {
            session.isUnlocked = true
            error = nil
            password = ""
        } else {
            attempts += 1
            error = "Senha incorreta. Tentativa \(attempts)."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

struct ChangePasswordView: View {
    let preferences: PreferencesStore
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alterar senha")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
            SecureField("Senha atual", text: $current)
                .secureFieldStyle()
            SecureField("Nova senha", text: $newPassword)
                .secureFieldStyle()
            SecureField("Confirmar nova senha", text: $confirmation)
                .secureFieldStyle()
            if let error { NoticeBanner(error, kind: .error) }
            Button("SALVAR") { change() }
                .buttonStyle(PrimaryActionButtonStyle())
            Spacer()
        }
        .padding(20)
    }

    private func change() {
        let hash = AdminCredential.hash(password: current, salt: preferences.value.adminPasswordSalt)
        guard hash == preferences.value.adminPasswordHash else {
            error = "Senha atual incorreta."
            return
        }
        if let message = AdminCredential.validate(password: newPassword) {
            error = message
            return
        }
        guard newPassword == confirmation else {
            error = "As senhas não coincidem."
            return
        }
        let salt = AdminCredential.makeSalt()
        let newHash = AdminCredential.hash(password: newPassword, salt: salt)
        preferences.update {
            $0.adminPasswordSalt = salt
            $0.adminPasswordHash = newHash
        }
        onDone()
        dismiss()
    }
}

private extension View {
    func secureFieldStyle() -> some View {
        self
            .textContentType(.password)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NexusTheme.Palette.stroke, lineWidth: 1))
    }
}

/// Full list of registered games with edit/delete.
struct AdminGameListSheet: View {
    @ObservedObject var catalog: CatalogStore
    var onEdit: (Game) -> Void
    var onDelete: (Game) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    private var filtered: [Game] {
        let term = SearchText.fold(search)
        guard !term.isEmpty else { return catalog.games }
        return catalog.games.filter { $0.searchableText.contains(term) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Jogos cadastrados")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Spacer()
                IconButton(systemName: "xmark", background: NexusTheme.Palette.surfaceSecondary) { dismiss() }
            }
            TextField("Filtrar por nome…", text: $search)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NexusTheme.Palette.surface))
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filtered) { game in
                        AdminGameRow(game: game, onEdit: { onEdit(game) }, onDelete: { onDelete(game) })
                        Rectangle().fill(NexusTheme.Palette.stroke).frame(height: 0.6)
                    }
                }
            }
        }
        .padding(20)
        .background(NexusTheme.Palette.backgroundElevated)
    }
}
