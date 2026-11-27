import Foundation

/// Events emitted by the engine while a job runs. Delivered **off** the main thread; the app hops to
/// the main actor before touching UI state.
public enum TransferEvent: Sendable {
    case state(TransferJob.State, message: String)
    case downloadProgress(downloaded: Int64, total: Int64)
    case uploadProgress(uploaded: Int64, total: Int64)
    /// Bytes per second measured over a sliding window.
    case speed(bytesPerSecond: Double, remainingSeconds: Double?)
    case finished(TransferJob)
}

/// Result of one transfer attempt.
public struct TransferResult: Sendable {
    public let job: TransferJob
    public let error: FTPError?
    public var succeeded: Bool { error == nil && job.state == .completed }
}

/// Abstraction over the network so the engine's control flow can be tested deterministically and the
/// app can plug in an authenticated, background-capable downloader on iOS.
public protocol TransferNetworking: Sendable {
    /// Downloads `remote` into `destination` (overwriting it is not allowed - the engine handles
    /// resume by passing a destination that already contains partial bytes).
    ///
    /// - Parameters:
    ///   - resumeFromByte: existing file size to continue from (Range header). 0 for a fresh start.
    ///   - progress: (bytesWrittenSoFar including resume offset, totalBytes if known)
    func download(
        from remote: URL,
        to destination: URL,
        resumeFromByte: Int64,
        progress: @escaping @Sendable (Int64, Int64) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> Int64

    func fileSize(for url: URL) -> Int64?
}

/// Sequential transfer queue.
///
/// Design notes:
/// - One job runs at a time. Wi-Fi is a shared resource and the PS4-side FTP servers are usually
///   single-connection, so parallel transfers would only slow each other down.
/// - Threading model: all mutable engine state is guarded by `lock`. Long-running work (download +
///   FTP dialogue) happens on a dedicated serial `workQueue`, one job at a time, which makes the
///   queue strictly sequential without ever blocking the caller. Callbacks from the network are
///   answered from the lock, never by re-entering the work queue (that would deadlock).
/// - Pause is only offered while **downloading** (HTTP Range supports it). Once the upload to the
///   console started, the job can only be cancelled — FTP has no portable resume guarantee, and
///   pretending otherwise could leave a corrupt package on the console.
public final class TransferEngine: @unchecked Sendable {

    public typealias EventHandler = @Sendable (UUID, TransferEvent) -> Void

    private let workingDirectory: URL
    private let networking: TransferNetworking
    private let ftpProvider: FTPSocketProvider
    private var configuration: TransferConfiguration
    private let fileManager: FileManager

    private let lock = NSLock()
    private var pendingJobs: [TransferJob] = []
    private var activeJob: TransferJob?
    private var cancelRequested = false
    private var pauseRequested = false
    private var eventHandler: EventHandler?
    private var currentSpeed: Double = 0
    private var remainingSeconds: Double?
    private var phase: TransferPhase = .idle
    private var activeStartedAt: Date?

    private let workQueue = DispatchQueue(label: "com.nexusstore.transfer.engine", qos: .utility)

    public init(
        workingDirectory: URL,
        networking: TransferNetworking,
        ftpProvider: FTPSocketProvider = BSDFTPSocketProvider(),
        configuration: TransferConfiguration = TransferConfiguration(),
        fileManager: FileManager = .default
    ) {
        self.workingDirectory = workingDirectory
        self.networking = networking
        self.ftpProvider = ftpProvider
        self.configuration = configuration
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Observation

    /// Applies new settings (temporary-file policy...) to the next jobs.
    public func updateConfiguration(_ configuration: TransferConfiguration) {
        lock.lock(); self.configuration = configuration; lock.unlock()
    }

    /// Registers the observer used to push UI updates.
    public func setEventHandler(_ handler: @escaping EventHandler) {
        lock.lock(); eventHandler = handler; lock.unlock()
    }

    public var currentJob: TransferJob? {
        lock.lock(); defer { lock.unlock() }
        return activeJob ?? pendingJobs.first
    }

    /// Latest measured speed in bytes/second (updated ~every 2 s during upload).
    public var currentSpeedBytesPerSecond: Double {
        lock.lock(); defer { lock.unlock() }
        return currentSpeed
    }

    /// Latest remaining-time estimate in seconds.
    public var estimatedRemainingSeconds: Double? {
        lock.lock(); defer { lock.unlock() }
        return remainingSeconds
    }

    /// Coarse phase used by the UI to show "Baixando" vs "Transferindo".
    public var currentPhase: TransferPhase {
        lock.lock(); defer { lock.unlock() }
        return phase
    }

    public var startedAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return activeStartedAt
    }

    public var queuedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pendingJobs.count
    }

    public var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        return activeJob != nil
    }

    // MARK: - Public API

    /// Adds a job to the end of the queue and starts it when the engine is idle.
    public func enqueue(_ job: TransferJob) {
        lock.lock()
        currentSpeed = 0
        remainingSeconds = nil
        pendingJobs.append(job)
        lock.unlock()
        emit(job.id, .state(.queued, message: "Na fila de transferência"))
        workQueue.async { [weak self] in
            self?.runNext()
        }
    }

    /// Requests a cooperative pause (download phase only). No-op otherwise.
    public func pause() {
        lock.lock()
        guard activeJob?.state == .downloading else { lock.unlock(); return }
        pauseRequested = true
        lock.unlock()
    }

    /// Cancels the active job (or removes a queued one).
    public func cancel(jobID: UUID) {
        lock.lock()
        if activeJob?.id == jobID {
            cancelRequested = true
            lock.unlock()
            return
        }
        if let index = pendingJobs.firstIndex(where: { $0.id == jobID }) {
            var job = pendingJobs.remove(at: index)
            lock.unlock()
            job.state = .cancelled
            job.message = "Removida da fila."
            emitState(job.id, .cancelled, job.message)
            emit(job.id, .finished(job))
            return
        }
        lock.unlock()
    }

    /// Cancels everything and clears the queue (used when the user leaves the PS4 area).
    public func cancelAll() {
        lock.lock()
        cancelRequested = true
        let queued = pendingJobs
        pendingJobs.removeAll()
        lock.unlock()
        for var job in queued {
            job.state = .cancelled
            job.message = "Fila esvaziada."
            emit(job.id, .finished(job))
        }
    }

    /// Deletes a job's temporary file.
    public func discardTemporaryFile(for job: TransferJob) {
        try? fileManager.removeItem(at: localURL(for: job))
    }

    /// Path of the temporary .pkg for a job (exposed for tests/debug screens).
    public func localURL(for job: TransferJob) -> URL {
        workingDirectory.appendingPathComponent("\(job.id.uuidString).pkg")
    }

    // MARK: - Runner (workQueue only)

    private func runNext() {
        lock.lock()
        guard activeJob == nil, !pendingJobs.isEmpty else {
            lock.unlock()
            return
        }
        var job = pendingJobs.removeFirst()
        job.state = .preparing
        job.startedAt = job.startedAt ?? Date()
        activeJob = job
        cancelRequested = false
        pauseRequested = false
        currentSpeed = 0
        remainingSeconds = nil
        activeStartedAt = Date()
        lock.unlock()

        emit(job.id, .state(.preparing, message: "Preparando transferência…"))
        let result = run(job)

        lock.lock()
        activeJob = nil
        activeStartedAt = nil
        lock.unlock()

        emit(result.job.id, .finished(result.job))
        runNext()
    }

    private func run(_ job: TransferJob) -> TransferResult {
        var job = job

        // 1. Validate the source link before touching the network.
        guard let sourceURL = HTTPSURLValidator.url(from: job.sourceURLString) else {
            job.state = .failed
            job.finishedAt = Date()
            job.message = "O link do jogo não é um endereço HTTPS válido. Atualize o cadastro no painel administrativo."
            emitState(job.id, .failed, job.message)
            return TransferResult(job: job, error: .localFile(job.message))
        }

        do {
            // 2. Download (with resume support).
            let localURL = localURL(for: job)
            let existing = Self.fileSize(at: localURL)
            job.state = .downloading
            emitState(job.id, .downloading, existing > 0 ? "Retomando download…" : "Baixando arquivo PKG…")
            let total = networking.fileSize(for: sourceURL) ?? job.expectedTotalBytes
            if total > 0, job.expectedTotalBytes != total {
                job.expectedTotalBytes = total
            }
            let jobID = job.id
            let downloaded = try networking.download(
                from: sourceURL,
                to: localURL,
                resumeFromByte: existing,
                progress: { [weak self] written, reported in
                    guard let self else { return }
                    let knownTotal = reported > 0 ? reported : max(total, written)
                    self.emit(jobID, .downloadProgress(downloaded: written, total: knownTotal))
                },
                isCancelled: { [weak self] in
                    guard let self else { return true }
                    return self.isCancellationOrPauseRequested
                }
            )

            if isPauseRequested {
                job.downloadedBytes = downloaded
                job.state = .paused
                job.message = "Download pausado (\(ByteFormatting.formatSize(downloaded)) baixados)."
                emitState(job.id, .paused, job.message)
                return TransferResult(job: job, error: nil)
            }
            if isCancelRequested {
                throw FTPError.cancelled
            }

            job.downloadedBytes = downloaded
            if job.expectedTotalBytes > 0, downloaded < job.expectedTotalBytes {
                throw FTPError.closedByServer
            }
            if job.expectedTotalBytes == 0 { job.expectedTotalBytes = downloaded }

            // 3. Upload to the console.
            job.state = .connecting
            emitState(job.id, .connecting, "Conectando ao console…")
            let client = FTPClient(provider: ftpProvider)
            try client.connectAndLogin(
                host: job.consoleHost,
                port: job.consolePort,
                user: job.consoleUsername,
                password: "",
                timeout: 20
            )
            if job.remotePath != "/" {
                _ = try? client.changeDirectory(job.remotePath)
            }

            job.state = .transferring
            emitState(job.id, .transferring, "Enviando para \(job.consoleName)…")
            let uploadResult = try uploadWithMetrics(client: client, job: job, localURL: localURL)

            // 4. Optional verification, only when the server actually implements SIZE.
            if configuration.verifyRemoteSizeWhenAvailable,
               let remoteSize = client.remoteFileSize(job.remoteFileName),
               remoteSize != uploadResult {
                throw FTPError.unexpectedReply(
                    command: "SIZE",
                    reply: "o arquivo remoto tem \(remoteSize) bytes, esperado \(uploadResult)"
                )
            }
            client.quitSilently()

            job.uploadedBytes = uploadResult
            job.state = .completed
            job.finishedAt = Date()
            job.message = "Envio concluído com sucesso."
            emitState(job.id, .completed, job.message)

            if configuration.deleteLocalFileWhenDone {
                try? fileManager.removeItem(at: localURL)
            }
            return TransferResult(job: job, error: nil)
        } catch let error as FTPError {
            job.finishedAt = Date()
            if error == .cancelled {
                job.state = .cancelled
                job.message = "Transferência cancelada."
                if configuration.cleanTemporaryFilesOnCancel {
                    try? fileManager.removeItem(at: localURL(for: job))
                }
            } else {
                job.state = .failed
                job.message = error.localizedDescription
                if job.uploadedBytes > 0 || job.downloadedBytes == 0 {
                    try? fileManager.removeItem(at: localURL(for: job))
                }
            }
            emitState(job.id, job.state, job.message)
            return TransferResult(job: job, error: error)
        } catch {
            job.finishedAt = Date()
            job.state = .failed
            job.message = error.localizedDescription
            emitState(job.id, .failed, job.message)
            return TransferResult(job: job, error: .localFile(error.localizedDescription))
        }
    }

    /// Uploads while measuring speed over a ~2 s sliding window.
    private func uploadWithMetrics(client: FTPClient, job: TransferJob, localURL: URL) throws -> Int64 {
        var windowStart = Date()
        var windowBytes: Int64 = 0
        var lastReport = Date.distantPast
        let startedAt = Date()

        return try client.upload(
            fileURL: localURL,
            remoteName: job.remoteFileName,
            progress: { [weak self] sent, total in
                guard let self else { return }
                self.emit(job.id, .uploadProgress(uploaded: sent, total: total))
                let now = Date()
                let elapsed = now.timeIntervalSince(windowStart)
                if elapsed >= 2.0 {
                    let speed = Double(windowBytes) / elapsed
                    let remaining = speed > 0 ? Double(max(total - sent, 0)) / speed : nil
                    self.emit(job.id, .speed(bytesPerSecond: speed, remainingSeconds: remaining))
                    windowStart = now
                    windowBytes = 0
                } else if now.timeIntervalSince(lastReport) > 4.0 {
                    // Always give the UI an average speed even on slow links.
                    let elapsedTotal = now.timeIntervalSince(startedAt)
                    let average = elapsedTotal > 0 ? Double(sent) / elapsedTotal : 0
                    let remaining = average > 0 ? Double(max(total - sent, 0)) / average : nil
                    self.emit(job.id, .speed(bytesPerSecond: average, remainingSeconds: remaining))
                    lastReport = now
                }
                windowBytes = sent
            },
            isCancelled: { [weak self] in
                guard let self else { return true }
                return self.isCancelRequested
            }
        )
    }

    // MARK: - Flags

    private var isCancellationOrPauseRequested: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelRequested || pauseRequested
    }

    private var isCancelRequested: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelRequested
    }

    private var isPauseRequested: Bool {
        lock.lock(); defer { lock.unlock() }
        return pauseRequested
    }

    // MARK: - Emission

    private func emitState(_ id: UUID, _ state: TransferJob.State, _ message: String) {
        emit(id, .state(state, message: message))
    }

    private func emit(_ id: UUID, _ event: TransferEvent) {
        lock.lock()
        switch event {
        case let .speed(bytes, remaining):
            currentSpeed = bytes
            remainingSeconds = remaining
        case let .state(state, _):
            phase = TransferPhase(state: state)
            if state.isRunning, activeStartedAt == nil { activeStartedAt = Date() }
            if state.isTerminal { activeStartedAt = nil }
        default:
            break
        }
        let handler = eventHandler
        lock.unlock()
        handler?(id, event)
    }

    static func fileSize(at url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
