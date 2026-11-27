import Foundation

/// A unit of work: download one .pkg from its catalog link, upload it to one console.
public struct TransferJob: Identifiable, Codable, Equatable, Sendable {

    public enum State: String, Codable, Sendable {
        case queued
        case preparing
        case downloading
        case connecting
        case transferring
        case paused
        case completed
        case failed
        case cancelled

        public var title: String {
            switch self {
            case .queued: return "AGUARDANDO"
            case .preparing: return "PREPARANDO"
            case .downloading: return "BAIXANDO"
            case .connecting: return "CONECTANDO"
            case .transferring: return "TRANSFERINDO"
            case .paused: return "PAUSADA"
            case .completed: return "CONCLUÍDO"
            case .failed: return "ERRO"
            case .cancelled: return "CANCELADA"
            }
        }

        public var isTerminal: Bool {
            switch self {
            case .completed, .failed, .cancelled: return true
            default: return false
            }
        }

        public var isRunning: Bool {
            switch self {
            case .preparing, .downloading, .connecting, .transferring: return true
            default: return false
            }
        }
    }

    public var id: UUID
    public var gameID: UUID
    public var gameName: String
    public var coverURLString: String
    public var sourceURLString: String
    public var remoteFileName: String
    public var consoleName: String
    public var consoleHost: String
    public var consolePort: UInt16
    public var consoleUsername: String
    public var remotePath: String
    /// Total size informed by the catalog (may be 0 when the admin left it blank).
    public var expectedTotalBytes: Int64
    /// Bytes downloaded to the iPhone.
    public var downloadedBytes: Int64
    /// Bytes accepted by the console (upload progress).
    public var uploadedBytes: Int64
    public var state: State
    public var message: String
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(
        id: UUID = UUID(),
        gameID: UUID,
        gameName: String,
        coverURLString: String,
        sourceURLString: String,
        remoteFileName: String,
        consoleName: String,
        consoleHost: String,
        consolePort: UInt16,
        consoleUsername: String = "anonymous",
        remotePath: String = "/",
        expectedTotalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        uploadedBytes: Int64 = 0,
        state: State = .queued,
        message: String = "",
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.gameID = gameID
        self.gameName = gameName
        self.coverURLString = coverURLString
        self.sourceURLString = sourceURLString
        self.remoteFileName = remoteFileName
        self.consoleName = consoleName
        self.consoleHost = consoleHost
        self.consolePort = consolePort
        self.consoleUsername = consoleUsername
        self.remotePath = remotePath
        self.expectedTotalBytes = expectedTotalBytes
        self.downloadedBytes = downloadedBytes
        self.uploadedBytes = uploadedBytes
        self.state = state
        self.message = message
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var totalBytes: Int64 { expectedTotalBytes }

    /// Percentage shown in the UI: download counts for its share, upload for the rest? No — the user
    /// cares about the console upload, so the ring shows the active phase; see `phaseProgress`.
    public var progress: Double {
        switch state {
        case .preparing, .queued: return 0
        case .downloading:
            return expectedTotalBytes > 0 ? min(1, Double(downloadedBytes) / Double(expectedTotalBytes)) : 0
        case .connecting: return expectedTotalBytes > 0 ? 1 : 0
        case .transferring, .completed, .failed, .cancelled:
            let total = expectedTotalBytes > 0 ? expectedTotalBytes : downloadedBytes
            return total > 0 ? min(1, Double(uploadedBytes) / Double(total)) : 0
        case .paused:
            return expectedTotalBytes > 0 ? min(1, Double(downloadedBytes) / Double(expectedTotalBytes)) : 0
        }
    }

    public var percentageText: String { String(format: "%.0f%%", progress * 100) }

    public var destinationDescription: String { "\(consoleName) • \(consoleHost)" }

    /// Only jobs that never reached the console may be retried safely from scratch.
    public var canRetry: Bool {
        switch state {
        case .failed, .cancelled: return true
        default: return false
        }
    }
}
