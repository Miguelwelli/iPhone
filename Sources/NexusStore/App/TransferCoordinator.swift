import Foundation
import SwiftUI

/// Observable bridge between the (thread-safe, non-UI) `TransferEngine` and SwiftUI.
///
/// It owns the visible job history, mirrors engine events on the main actor and exposes the derived
/// values the transfer screen renders (percentage, speed, remaining time).
@MainActor
public final class TransferCoordinator: ObservableObject {

    @Published public private(set) var jobs: [TransferJob] = []
    @Published public private(set) var activeJobID: UUID?
    @Published public private(set) var speed: Double = 0
    @Published public private(set) var remainingSeconds: Double?
    @Published public private(set) var phase: TransferPhase = .idle
    @Published public private(set) var startedAt: Date?
    @Published public var lastError: String?

    private let engine: TransferEngine
    private let networking: TransferNetworking
    private var cancellables: [UUID] = []

    public init(
        workingDirectory: URL,
        networking: TransferNetworking? = nil,
        ftpProvider: FTPSocketProvider = BSDFTPSocketProvider(),
        configuration: TransferConfiguration = TransferConfiguration()
    ) {
        self.networking = networking ?? URLSessionTransferNetworking()
        self.engine = TransferEngine(
            workingDirectory: workingDirectory,
            networking: self.networking,
            ftpProvider: ftpProvider,
            configuration: configuration
        )
        engine.setEventHandler { [weak self] jobID, event in
            Task { @MainActor [weak self] in
                self?.handle(jobID: jobID, event: event)
            }
        }
    }

    // MARK: - Public API

    public var activeJob: TransferJob? {
        guard let activeJobID else { return nil }
        return jobs.first { $0.id == activeJobID }
    }

    public var queuedJobs: [TransferJob] {
        jobs.filter { $0.state == .queued }
    }

    public var history: [TransferJob] {
        jobs.filter { $0.state.isTerminal }
    }

    public var hasActiveTransfer: Bool {
        guard let activeJob else { return false }
        return activeJob.state.isRunning || activeJob.state == .paused
    }

    /// Launches a job for a game on a console.
    public func send(game: Game, to console: ConsoleProfile) -> Bool {
        guard let source = game.downloadURL else {
            lastError = "O jogo “\(game.name)” não possui um link HTTPS válido para o arquivo .pkg."
            return false
        }
        let requiredSpace = game.byteCount
        let free = NexusFileStorage.freeDiskSpace()
        if requiredSpace > 0, free > 0, free < requiredSpace + 256 * 1024 * 1024 {
            lastError = "Espaço insuficiente no iPhone para baixar \(ByteFormatting.formatSize(requiredSpace)). Libere espaço e tente novamente."
            return false
        }

        let job = TransferJob(
            gameID: game.id,
            gameName: game.name,
            coverURLString: game.coverURLString,
            sourceURLString: source.absoluteString,
            remoteFileName: game.remotePackageName,
            consoleName: console.name,
            consoleHost: console.host,
            consolePort: console.port,
            consoleUsername: console.username,
            remotePath: console.remotePath,
            expectedTotalBytes: game.byteCount
        )
        jobs.insert(job, at: 0)
        activeJobID = job.id
        engine.enqueue(job)
        return true
    }

    public func pause() {
        engine.pause()
    }

    /// Resumes a paused download: the engine keeps the partial file and continues with a Range header.
    public func resume(_ job: TransferJob) {
        var resumed = job
        resumed.state = .queued
        resumed.message = "Retomando…"
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = resumed
        }
        activeJobID = job.id
        engine.enqueue(resumed)
    }

    public func cancel(_ job: TransferJob) {
        engine.cancel(jobID: job.id)
    }

    public func cancelAll() {
        engine.cancelAll()
    }

    public func remove(_ job: TransferJob) {
        engine.discardTemporaryFile(for: job)
        jobs.removeAll { $0.id == job.id }
        if activeJobID == job.id { activeJobID = nil }
    }

    public func clearHistory() {
        for job in history {
            engine.discardTemporaryFile(for: job)
        }
        jobs.removeAll { $0.state.isTerminal }
        if let active = activeJobID, !jobs.contains(where: { $0.id == active }) { activeJobID = nil }
    }

    /// Applies new transfer settings immediately (used by the settings sheet).
    public func updateConfiguration(_ configuration: TransferConfiguration) {
        engine.updateConfiguration(configuration)
    }

    // MARK: - Event handling

    private func handle(jobID: UUID, event: TransferEvent) {
        switch event {
        case let .state(state, message):
            phase = TransferPhase(state: state)
            if var job = jobs.first(where: { $0.id == jobID }) {
                job.state = state
                job.message = message
                if state.isRunning || state == .paused {
                    activeJobID = jobID
                }
                if state.isTerminal {
                    job.finishedAt = Date()
                    if activeJobID == jobID { activeJobID = nil }
                    speed = 0
                    remainingSeconds = nil
                }
                update(job)
            }
            if state == .failed { lastError = message }
        case let .downloadProgress(downloaded, total):
            guard var job = jobs.first(where: { $0.id == jobID }) else { return }
            job.downloadedBytes = downloaded
            if total > 0 { job.expectedTotalBytes = total }
            update(job)
        case let .uploadProgress(uploaded, total):
            guard var job = jobs.first(where: { $0.id == jobID }) else { return }
            job.uploadedBytes = uploaded
            if total > 0 { job.expectedTotalBytes = total }
            update(job)
        case let .speed(bytesPerSecond, estimate):
            speed = ProgressMath.smoothed(previous: speed, sample: bytesPerSecond)
            remainingSeconds = estimate
        case .finished(let job):
            update(job)
            if activeJobID == jobID { activeJobID = nil }
            phase = TransferPhase(state: job.state)
            speed = 0
            remainingSeconds = nil
            if job.state == .failed { lastError = job.message }
        }
    }

    private func update(_ job: TransferJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        }
    }
}
