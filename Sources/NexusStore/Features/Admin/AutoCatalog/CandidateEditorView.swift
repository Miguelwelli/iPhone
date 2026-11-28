import SwiftUI
import UIKit

/// Edição de um candidato antes da aprovação: todos os campos que irão para o catálogo, mais a
/// verificação real do link .PKG e o cadastro de uma fonte autorizada.
struct CandidateEditorView: View {
    let candidate: CatalogCandidate
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var assistant: AutoCatalogStore

    let onSave: (CatalogCandidate) -> Void
    let onReject: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draft: CatalogCandidate
    @State private var isCheckingLink = false
    @State private var linkMessage: String?
    @State private var showRejectConfirmation = false

    init(
        candidate: CatalogCandidate,
        catalog: CatalogStore,
        assistant: AutoCatalogStore,
        onSave: @escaping (CatalogCandidate) -> Void,
        onReject: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.catalog = catalog
        self.assistant = assistant
        self.onSave = onSave
        self.onReject = onReject
        _draft = State(initialValue: candidate)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                TitleField(draft: $draft)
                categoriesCard
                detailsCard
                pkgCard
                sourcesCard
                NoticeBanner(
                    "Nada aqui é inventado: campos vazios continuam vazios até você preencher com uma fonte que possa verificar.",
                    kind: .info
                )
                actions
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(
                reference: ArtworkReference(rawValue: draft.coverURLString),
                initials: "IA"
            )
            .frame(width: 52, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Editar antes de aprovar")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                Text("Origem: \(draft.sources.first?.name ?? "fonte externa")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            }
            Spacer()
            IconButton(systemName: "xmark", background: NexusTheme.Palette.surfaceSecondary) { dismiss() }
        }
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Categorias")
            FlowLayout(spacing: 8) {
                ForEach(GameCategory.all) { category in
                    let isOn = draft.categories.contains(category.rawValue)
                    Button {
                        if isOn {
                            draft.categories.removeAll { $0 == category.rawValue }
                        } else {
                            draft.categories.append(category.rawValue)
                        }
                    } label: {
                        Text(category.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isOn ? Color.white : NexusTheme.Palette.textSecondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(isOn ? NexusTheme.Palette.red : Color.clear))
                            .overlay(Capsule().stroke(isOn ? Color.clear : NexusTheme.Palette.strokeStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Dados do catálogo")
            HStack(spacing: 10) {
                field("Tamanho (ex.: 48.5 GB)", text: $draft.sizeText)
                field("Versão", text: $draft.version)
            }
            field("Plataforma", text: $draft.platformTag)
            field("Desenvolvedora", text: $draft.developer)
            field("Publicadora", text: $draft.publisher)
            field("Classificação", text: $draft.ageRating)
            VStack(alignment: .leading, spacing: 4) {
                label("Descrição")
                TextEditor(text: $draft.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(NexusTheme.Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(height: 96)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(NexusTheme.Palette.surfaceSecondary)
                    )
            }
            HStack(spacing: 10) {
                field("Capa (URL https)", text: $draft.coverURLString)
            }
            field("Banner (URL https)", text: $draft.bannerURLString)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var pkgCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Link PKG (fonte autorizada)")
            TextField("https://…/jogo.pkg", text: $draft.downloadURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NexusTheme.Palette.surfaceSecondary)
                )

            HStack(spacing: 10) {
                Button {
                    Task { await checkLink() }
                } label: {
                    HStack(spacing: 5) {
                        if isCheckingLink {
                            ProgressView().tint(NexusTheme.Palette.redBright).scaleEffect(0.6)
                        }
                        Text("Verificar link")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(NexusTheme.Palette.redBright)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(NexusTheme.Palette.red.opacity(0.55), lineWidth: 1)
                    )
                }
                .disabled(isCheckingLink || draft.downloadURLString.isEmpty)

                Text(draft.pkgStatus.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(draft.pkgStatus.isVerified ? NexusTheme.Palette.success : NexusTheme.Palette.textTertiary)
            }

            Text(linkMessage ?? draft.pkgStatus.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            NoticeBanner(
                "A verificação apenas confirma que o endereço responde e entrega um binário — ela não prova licenciamento. Cadastre somente arquivos que você tem o direito de distribuir.",
                kind: .warning
            )
        }
        .padding(14)
        .background(cardBackground)
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Fontes das informações")
            if draft.sources.isEmpty {
                Text("Nenhuma fonte registrada.")
                    .font(.system(size: 11))
                    .foregroundStyle(NexusTheme.Palette.textTertiary)
            } else {
                ForEach(draft.sources) { source in
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                            .foregroundStyle(NexusTheme.Palette.textTertiary)
                        Text(source.urlString.isEmpty ? source.name : "\(source.name) — \(source.urlString)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(NexusTheme.Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                onSave(draft)
                dismiss()
            } label: {
                Text("SALVAR ALTERAÇÕES")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())

            Button {
                showRejectConfirmation = true
            } label: {
                Text("Rejeitar este jogo")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NexusTheme.Palette.danger)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .confirmationDialog("Rejeitar “\(draft.title)”?", isPresented: $showRejectConfirmation, titleVisibility: .visible) {
            Button("Rejeitar", role: .destructive) {
                onReject()
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private func checkLink() async {
        isCheckingLink = true
        defer { isCheckingLink = false }
        let status = await PKGLinkVerifier().verify(draft.downloadURLString)
        draft.pkgStatus = status
        linkMessage = status.detail
        if status.isVerified {
            // Remember the authorized source so the next search reuses it for this title.
            assistant.setPKGLink(draft.downloadURLString, forTitle: draft.title)
        }
        UINotificationFeedbackGenerator().notificationOccurred(status.isVerified ? .success : .error)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
            .fill(NexusTheme.Palette.surface.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                    .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
            )
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(NexusTheme.Palette.textTertiary)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            TextField("—", text: text)
                .font(.system(size: 12.5))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NexusTheme.Palette.surfaceSecondary)
                )
        }
    }
}

/// Title field kept separate so the editor body stays inside the type-checker's budget.
private struct TitleField: View {
    @Binding var draft: CatalogCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOME DO JOGO")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            TextField("Nome", text: $draft.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NexusTheme.Palette.surfaceSecondary)
                )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                .fill(NexusTheme.Palette.surface.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                        .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
                )
        )
    }
}
