import SwiftUI
import UIKit

/// Revisão da IA — cards com capa, metadados, fonte, validação do link e ações de aprovação.
struct AutoCatalogReviewView: View {
    @ObservedObject var assistant: AutoCatalogStore
    @ObservedObject var catalog: CatalogStore
    let searchID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var editingCandidate: CatalogCandidate?
    @State private var toast: String?
    @State private var showApproveAllConfirmation = false

    private var search: AutoCatalogSearch? { assistant.search(id: searchID) }
    private var candidates: [CatalogCandidate] { search?.candidates ?? [] }
    private var pending: [CatalogCandidate] { candidates.filter { $0.state == .pending } }

    var body: some View {
        ZStack {
            NexusBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    subtitleBar
                    if let search {
                        if let error = search.errorMessage {
                            NoticeBanner(error, kind: .error)
                        }
                        if candidates.isEmpty && search.errorMessage == nil {
                            EmptyStateView(
                                icon: "sparkles",
                                title: "Nenhum jogo encontrado",
                                message: "A fonte consultada não devolveu títulos novos para estas categorias. Ajuste os parâmetros e repita a busca."
                            )
                            .padding(.top, 20)
                        } else if candidates.isEmpty {
                            EmptyStateView(
                                icon: "exclamationmark.triangle",
                                title: "A busca não foi concluída",
                                message: "Nada foi cadastrado. Volte, corrija a chave e tente novamente."
                            )
                            .padding(.top, 20)
                        } else {
                            ForEach(candidates) { candidate in
                                candidateCard(candidate)
                            }
                        }
                    }
                    if let url = URL(string: "https://rawg.io") {
                        Link(destination: url) {
                            Text("Dados e imagens: RAWG Video Games Database")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(NexusTheme.Palette.redBright)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Color.clear.frame(height: pending.isEmpty ? 16 : 96)
                }
                .padding(.horizontal, NexusTheme.Metrics.screenPadding)
                .padding(.top, 6)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !pending.isEmpty {
                approveAllBar
            }
        }
        .overlay(alignment: .top) { toastView }
        .sheet(item: $editingCandidate) { candidate in
            NexusSheetChrome {
                CandidateEditorView(
                    candidate: candidate,
                    catalog: catalog,
                    assistant: assistant,
                    onSave: { updated in
                        assistant.update(candidate: updated, in: searchID)
                        toast = "Alterações salvas em “\(updated.title)”"
                    },
                    onReject: {
                        assistant.reject(candidateID: candidate.id, in: searchID)
                        toast = "“\(candidate.title)” rejeitado"
                    }
                )
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(
            "Aprovar todos os jogos prontos?",
            isPresented: $showApproveAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Aprovar \(search?.readyCount ?? 0) jogos") { approveAll() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Jogos com dados incompletos (sem tamanho válido ou com link não verificado) não serão cadastrados.")
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(systemName: "chevron.left", background: .clear) { dismiss() }
            Spacer()
            Text("Revisão da IA (\(candidates.count) encontrados)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer()
            IconButton(systemName: "checkmark.circle", background: .clear) {
                showApproveAllConfirmation = true
            }
            .disabled(pending.isEmpty)
            .opacity(pending.isEmpty ? 0.4 : 1)
            .accessibilityLabel("Aprovar todos")
        }
    }

    private var subtitleBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Categoria: \(categorySummary) • \(search?.providerName ?? "fonte externa")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if search?.errorMessage == nil {
                    HStack(spacing: 5) {
                        Circle().fill(NexusTheme.Palette.success).frame(width: 6, height: 6)
                        Text("\(search?.readyCount ?? 0) PRONTOS")
                            .font(.system(size: 9.5, weight: .bold))
                            .kerning(0.3)
                            .foregroundStyle(NexusTheme.Palette.success)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(NexusTheme.Palette.success.opacity(0.12)))
                    .overlay(Capsule().stroke(NexusTheme.Palette.success.opacity(0.35), lineWidth: 1))
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(NexusTheme.Palette.danger).frame(width: 6, height: 6)
                        Text("FALHOU")
                            .font(.system(size: 9.5, weight: .bold))
                            .kerning(0.3)
                            .foregroundStyle(NexusTheme.Palette.danger)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(NexusTheme.Palette.danger.opacity(0.12)))
                    .overlay(Capsule().stroke(NexusTheme.Palette.danger.opacity(0.35), lineWidth: 1))
                }
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

    private var categorySummary: String {
        guard let search else { return "—" }
        let titles = search.request.categories.map { GameCategory.title(for: $0) }
        return titles.isEmpty ? "Todas" : titles.joined(separator: " / ")
    }

    @ViewBuilder
    private var toastView: some View {
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

    // MARK: - Card

    private func candidateCard(_ candidate: CatalogCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ArtworkView(
                    reference: ArtworkReference(rawValue: candidate.coverURLString),
                    initials: Self.initials(candidate.title)
                )
                .frame(width: 74, height: 111)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NexusTheme.Palette.textPrimary)
                        .lineLimit(2)

                    Text(specLine(candidate))
                        .font(.system(size: 12))
                        .foregroundStyle(NexusTheme.Palette.textSecondary)

                    pkgBadge(candidate.pkgStatus)

                    if !candidate.downloadURLString.isEmpty {
                        Text(candidate.downloadURLString)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(NexusTheme.Palette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if candidate.state == .approved {
                        Label("Cadastrado no catálogo", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.success)
                    } else if candidate.state == .rejected {
                        Label("Rejeitado", systemImage: "xmark.circle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.danger)
                    }
                }
                Spacer(minLength: 0)
            }

            if !candidate.summary.isEmpty {
                Text(candidate.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(NexusTheme.Palette.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MetadataGrid(candidate: candidate)

            if !candidate.sources.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FONTES")
                        .font(.system(size: 9, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(NexusTheme.Palette.textTertiary)
                    ForEach(candidate.sources) { source in
                        if let url = URL(string: source.urlString) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                    Text(source.name)
                                }
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(NexusTheme.Palette.redBright)
                            }
                        } else {
                            Text(source.name)
                                .font(.system(size: 10.5))
                                .foregroundStyle(NexusTheme.Palette.textSecondary)
                        }
                    }
                }
            }

            if !candidate.isReady && candidate.state == .pending {
                NoticeBanner(candidate.blockingIssues().joined(separator: " "), kind: .warning)
            }

            if candidate.state == .pending {
                HStack(spacing: 10) {
                    Button {
                        editingCandidate = candidate
                    } label: {
                        Text("Editar / Rejeitar")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(NexusTheme.Palette.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(NexusTheme.Palette.surfaceSecondary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(NexusTheme.Palette.strokeStrong, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        approve(candidate)
                    } label: {
                        Text("Aprovar e Cadastrar")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(candidate.isReady ? NexusTheme.Palette.red : NexusTheme.Palette.surfaceSecondary)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!candidate.isReady)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                .fill(NexusTheme.Palette.surface.opacity(candidate.state == .rejected ? 0.35 : 0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Metrics.cardRadius, style: .continuous)
                .stroke(NexusTheme.Palette.stroke, lineWidth: 1)
        )
        .opacity(candidate.state == .rejected ? 0.7 : 1)
    }

    private func specLine(_ candidate: CatalogCandidate) -> String {
        var parts: [String] = []
        if !candidate.sizeText.isEmpty { parts.append(candidate.sizeText) }
        if !candidate.version.isEmpty { parts.append("v\(candidate.version)") }
        parts.append("PS4")
        let categories = candidate.categories.map { GameCategory.title(for: $0) }
        if !categories.isEmpty { parts.append(categories.joined(separator: " / ")) }
        return parts.joined(separator: " • ")
    }

    @ViewBuilder
    private func pkgBadge(_ status: PKGLinkStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .verified:
                return (status.label, NexusTheme.Palette.success)
            case .rejected:
                return (status.label, NexusTheme.Palette.danger)
            case .notChecked:
                return (status.label, NexusTheme.Palette.warning)
            case .notProvided:
                return (status.label, NexusTheme.Palette.textTertiary)
            }
        }()
        HStack(spacing: 4) {
            Image(systemName: status.isVerified ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private var approveAllBar: some View {
        VStack(spacing: 8) {
            Button {
                showApproveAllConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("APROVAR TODOS OS \((search?.readyCount ?? 0)) JOGOS")
                        .font(.system(size: 13.5, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled((search?.readyCount ?? 0) == 0)

            Text("Adiciona todos os títulos validados ao catálogo da Nexus Store")
                .font(.system(size: 9.5))
                .foregroundStyle(NexusTheme.Palette.textTertiary)
        }
        .padding(.horizontal, NexusTheme.Metrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [NexusTheme.Palette.background.opacity(0), NexusTheme.Palette.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions

    private func approve(_ candidate: CatalogCandidate) {
        switch assistant.approve(candidate, in: searchID) {
        case .success(let game):
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            toast = "“\(game.name)” cadastrado no catálogo"
        case .failure(let error):
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            toast = error.errorDescription ?? "Não foi possível cadastrar"
        }
    }

    private func approveAll() {
        let result = assistant.approveAll(in: searchID)
        UINotificationFeedbackGenerator().notificationOccurred(result.approved > 0 ? .success : .error)
        if result.skipped > 0 {
            toast = "\(result.approved) cadastrados • \(result.skipped) precisam de ajustes"
        } else {
            toast = "\(result.approved) jogos cadastrados no catálogo"
        }
    }

    private static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

/// Compact technical summary shown under each candidate.
private struct MetadataGrid: View {
    let candidate: CatalogCandidate

    var body: some View {
        let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            item("Tamanho", candidate.sizeText.isEmpty ? "A informar" : candidate.sizeText)
            item("Versão", candidate.version.isEmpty ? "A informar" : candidate.version)
            item("Plataforma", candidate.platformTag)
            item("Gênero", candidate.categories.isEmpty ? "—" : candidate.categories.map { GameCategory.title(for: $0) }.joined(separator: ", "))
            if !candidate.developer.isEmpty { item("Desenvolvedora", candidate.developer) }
            if !candidate.publisher.isEmpty { item("Publicadora", candidate.publisher) }
        }
    }

    private func item(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .kerning(0.4)
                .foregroundStyle(NexusTheme.Palette.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NexusTheme.Palette.textPrimary)
                .lineLimit(2)
        }
    }
}
