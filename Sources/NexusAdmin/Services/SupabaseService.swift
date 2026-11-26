import Foundation

enum NexusError: LocalizedError {
    case notConfigured
    case invalidURL
    case serverError(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Configure a URL e a chave pública do Supabase em Ajustes."
        case .invalidURL:
            return "URL do servidor Supabase inválida."
        case .serverError(let code, let message):
            return "Erro do servidor (\(code)): \(message)"
        case .decodingError:
            return "Não foi possível interpretar a resposta do servidor."
        }
    }
}

@MainActor
final class SupabaseService: ObservableObject {
    @Published var config: SupabaseConfig {
        didSet { saveConfig() }
    }
    @Published var games: [Game] = []
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    private let configKey = "nexus_admin_supabase_config"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: "nexus_admin_supabase_config"),
           let saved = try? JSONDecoder().decode(SupabaseConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = SupabaseConfig(projectURL: "", anonKey: "", accessToken: "")
        }
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json") throws -> URLRequest {
        guard config.isConfigured else { throw NexusError.notConfigured }
        guard let url = URL(string: "\(config.normalizedURL)\(path)") else { throw NexusError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        let bearer = config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? config.anonKey
            : config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    func testConnection() async -> Bool {
        guard config.isConfigured else {
            isConnected = false
            return false
        }
        do {
            let req = try makeRequest(path: "/rest/v1/games?select=id&limit=1")
            let (_, response) = try await URLSession.shared.data(for: req)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            isConnected = ok
            return ok
        } catch {
            isConnected = false
            return false
        }
    }

    func fetchGames() async {
        guard config.isConfigured else {
            isConnected = false
            games = []
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let req = try makeRequest(path: "/rest/v1/games?select=*&order=created_at.desc")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw NexusError.invalidURL }
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "Erro desconhecido"
                isConnected = false
                throw NexusError.serverError(http.statusCode, msg)
            }
            games = try decoder.decode([Game].self, from: data)
            isConnected = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func uploadImage(data: Data, bucket: String, fileName: String) async throws -> String {
        let cleanName = fileName.replacingOccurrences(of: " ", with: "_")
        var req = try makeRequest(
            path: "/storage/v1/object/\(bucket)/\(cleanName)",
            method: "POST",
            body: data,
            contentType: "image/jpeg"
        )
        req.setValue("true", forHTTPHeaderField: "x-upsert")

        let (respData, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NexusError.invalidURL }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: respData, encoding: .utf8) ?? "Falha no upload"
            throw NexusError.serverError(http.statusCode, msg)
        }
        return "\(config.normalizedURL)/storage/v1/object/public/\(bucket)/\(cleanName)"
    }

    func publishGame(_ game: Game) async throws {
        var newGame = game
        newGame.published = true
        newGame.created_at = Date()
        newGame.updated_at = Date()

        let body = try encoder.encode(newGame)
        var req = try makeRequest(path: "/rest/v1/games", method: "POST", body: body)
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NexusError.invalidURL }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Falha ao publicar"
            throw NexusError.serverError(http.statusCode, msg)
        }
        await fetchGames()
    }

    func updateGame(_ game: Game) async throws {
        var updated = game
        updated.updated_at = Date()

        let body = try encoder.encode(updated)
        var req = try makeRequest(path: "/rest/v1/games?id=eq.\(game.id.uuidString)", method: "PATCH", body: body)
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NexusError.invalidURL }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Falha ao atualizar"
            throw NexusError.serverError(http.statusCode, msg)
        }
        await fetchGames()
    }

    func deleteGame(id: UUID) async throws {
        let req = try makeRequest(path: "/rest/v1/games?id=eq.\(id.uuidString)", method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NexusError.invalidURL }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Falha ao excluir"
            throw NexusError.serverError(http.statusCode, msg)
        }
        games.removeAll { $0.id == id }
    }
}
