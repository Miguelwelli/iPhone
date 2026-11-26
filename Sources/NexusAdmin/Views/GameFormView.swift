import SwiftUI
import PhotosUI

struct GameFormView: View {
    @ObservedObject var service: SupabaseService
    var editingGame: Game?
    var onSaved: () -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var category: String = GameCategory.action.rawValue
    @State private var platform: String = GamePlatform.ps4.rawValue
    @State private var size: String = ""
    @State private var downloadURL: String = ""
    @State private var publishDate: Date = Date()

    @State private var coverItem: PhotosPickerItem?
    @State private var coverData: Data?
    @State private var existingCoverURL: String = ""

    @State private var bannerItem: PhotosPickerItem?
    @State private var bannerData: Data?
    @State private var existingBannerURL: String = ""

    @State private var isSubmitting: Bool = false
    @State private var feedbackMessage: String?
    @State private var isErrorFeedback: Bool = false

    private var isEditing: Bool { editingGame != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                titleHeader

                if let feedback = feedbackMessage {
                    HStack(spacing: 10) {
                        Image(systemName: isErrorFeedback ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        Text(feedback)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .foregroundStyle(isErrorFeedback ? NexusTheme.errorRed : NexusTheme.successGreen)
                    .padding(14)
                    .nexusCard(cornerRadius: 14)
                }

                VStack(spacing: 14) {
                    inputField(title: "Nome do jogo *", placeholder: "Ex: God of War Ragnarök", text: $name)
                    coverPickerSection
                    bannerPickerSection

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Descrição *")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NexusTheme.textSecondary)
                        TextEditor(text: $description)
                            .frame(minHeight: 96)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .foregroundStyle(NexusTheme.textPrimary)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(NexusTheme.cardBorder, lineWidth: 1)
                            )
                    }

                    pickerRow(title: "Categoria *", selection: $category, options: GameCategory.allCases.map(\.rawValue))
                    pickerRow(title: "Plataforma *", selection: $platform, options: GamePlatform.allCases.map(\.rawValue))

                    inputField(title: "Tamanho informado *", placeholder: "Ex: 42.5 GB", text: $size)
                    inputField(title: "URL externa do conteúdo *", placeholder: "https://...", text: $downloadURL, keyboard: .URL)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Data de publicação")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NexusTheme.textSecondary)
                        DatePicker("", selection: $publishDate, displayedComponents: .date)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(16)
                .nexusCard()

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: isEditing ? "checkmark.circle.fill" : "paperplane.fill")
                        }
                        Text(isSubmitting ? "PUBLICANDO..." : (isEditing ? "SALVAR ALTERAÇÕES" : "PUBLICAR"))
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [NexusTheme.electricBlue, NexusTheme.electricGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(isSubmitting)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(NexusTheme.backgroundGradient.ignoresSafeArea())
        .onAppear(perform: loadEditingData)
        .onChange(of: coverItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    coverData = data
                }
            }
        }
        .onChange(of: bannerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    bannerData = data
                }
            }
        }
    }

    private var titleHeader: some View {
        HStack {
            Text(isEditing ? "Editar Jogo" : "Cadastrar Jogo")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(NexusTheme.textPrimary)
            Spacer()
        }
    }

    private func inputField(title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NexusTheme.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .URL)
                .padding(12)
                .foregroundStyle(NexusTheme.textPrimary)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NexusTheme.cardBorder, lineWidth: 1)
                )
        }
    }

    private func pickerRow(title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NexusTheme.textSecondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(NexusTheme.electricGlow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var coverPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capa do jogo *")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NexusTheme.textSecondary)

            PhotosPicker(selection: $coverItem, matching: .images) {
                HStack(spacing: 12) {
                    if let data = coverData, let uiImg = UIImage(data: data) {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else if !existingCoverURL.isEmpty {
                        AsyncImage(url: URL(string: existingCoverURL)) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.1)
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(NexusTheme.electricGlow)
                            .frame(width: 60, height: 60)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(coverData != nil || !existingCoverURL.isEmpty ? "Alterar capa selecionada" : "Selecionar capa da galeria")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NexusTheme.textPrimary)
                        Text("Obrigatório • JPG ou PNG")
                            .font(.caption)
                            .foregroundStyle(NexusTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var bannerPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Banner (opcional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NexusTheme.textSecondary)

            PhotosPicker(selection: $bannerItem, matching: .images) {
                HStack(spacing: 12) {
                    Image(systemName: bannerData != nil || !existingBannerURL.isEmpty ? "checkmark.rectangle.fill" : "rectangle.badge.plus")
                        .font(.title3)
                        .foregroundStyle(NexusTheme.electricGlow)
                    Text(bannerData != nil || !existingBannerURL.isEmpty ? "Banner selecionado" : "Selecionar banner da galeria")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(NexusTheme.textPrimary)
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func loadEditingData() {
        guard let g = editingGame else { return }
        name = g.name
        description = g.description
        category = g.category
        platform = g.platform
        size = g.size
        downloadURL = g.download_url
        publishDate = g.created_at
        existingCoverURL = g.cover_url
        existingBannerURL = g.banner_url ?? ""
    }

    private func submit() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSize = size.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = downloadURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty,
              !trimmedDesc.isEmpty,
              !trimmedSize.isEmpty,
              !trimmedURL.isEmpty,
              URL(string: trimmedURL) != nil else {
            isErrorFeedback = true
            feedbackMessage = "Preencha todos os campos obrigatórios e informe uma URL válida."
            return
        }

        guard coverData != nil || !existingCoverURL.isEmpty else {
            isErrorFeedback = true
            feedbackMessage = "Selecione uma capa da galeria do iPhone."
            return
        }

        isSubmitting = true
        feedbackMessage = nil
        defer { isSubmitting = false }

        do {
            let gameID = editingGame?.id ?? UUID()
            var finalCoverURL = existingCoverURL
            if let cData = coverData {
                finalCoverURL = try await service.uploadImage(
                    data: cData,
                    bucket: "covers",
                    fileName: "\(gameID.uuidString).jpg"
                )
            }

            var finalBannerURL: String? = existingBannerURL.isEmpty ? nil : existingBannerURL
            if let bData = bannerData {
                finalBannerURL = try await service.uploadImage(
                    data: bData,
                    bucket: "banners",
                    fileName: "\(gameID.uuidString).jpg"
                )
            }

            let game = Game(
                id: gameID,
                name: trimmedName,
                cover_url: finalCoverURL,
                banner_url: finalBannerURL,
                description: trimmedDesc,
                category: category,
                platform: platform,
                size: trimmedSize,
                download_url: trimmedURL,
                published: true,
                created_at: publishDate,
                updated_at: Date()
            )

            if isEditing {
                try await service.updateGame(game)
                isErrorFeedback = false
                feedbackMessage = "Jogo atualizado e publicado com sucesso!"
            } else {
                try await service.publishGame(game)
                isErrorFeedback = false
                feedbackMessage = "Jogo publicado imediatamente no catálogo!"
                resetForm()
            }
            onSaved()
        } catch {
            isErrorFeedback = true
            feedbackMessage = error.localizedDescription
        }
    }

    private func resetForm() {
        name = ""
        description = ""
        size = ""
        downloadURL = ""
        coverItem = nil
        coverData = nil
        bannerItem = nil
        bannerData = nil
        existingCoverURL = ""
        existingBannerURL = ""
    }
}
