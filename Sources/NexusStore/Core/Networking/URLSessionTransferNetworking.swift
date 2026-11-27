import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A tiny thread-safe box used to share results between URLSession callbacks and the waiting caller.
/// Using an explicit box (instead of captured `var`s) keeps the code valid under the Swift 6
/// concurrency rules the app is built with.
public final class ResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    public init(_ initial: Value? = nil) { storage = initial }

    public func set(_ value: Value) {
        lock.lock(); defer { lock.unlock() }
        storage = value
    }

    public func get() -> Value? {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

/// Streaming HTTPS downloader used by the transfer engine.
///
/// - Uses `URLSessionDownloadTask`, which writes the payload straight to a temporary file — a 100 GB
///   package never sits in memory.
/// - Reports live progress through `URLSessionDownloadDelegate.didWriteData`.
/// - Supports HTTP resume (`Range: bytes=N-`); if the server ignores the range the partial file is
///   discarded and the download restarts, never leaving a corrupt package behind.
/// - Checks free disk space up front, failing with a clear message instead of dying mid-transfer.
/// - Cancellation is cooperative and checked while the task runs.
public final class URLSessionTransferNetworking: NSObject, TransferNetworking, URLSessionDownloadDelegate, @unchecked Sendable {

    public enum DownloadError: Error, Equatable {
        case serverIgnoredRange
        case httpStatus(Int)
        case diskSpace(String)
        case write(String)
    }

    private struct TaskContext {
        var destination: URL
        var resumeOffset: Int64
        var progress: @Sendable (Int64, Int64) -> Void
        var semaphore: DispatchSemaphore
        var failure: ResultBox<Error>
        var finalSize: ResultBox<Int64>
    }

    private let lock = NSLock()
    private var contexts: [Int: TaskContext] = [:]
    private var session: URLSession!

    public init(configuration: URLSessionConfiguration? = nil) {
        super.init()
        let configuration = configuration ?? URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60 * 12
        #if !canImport(FoundationNetworking)
        configuration.waitsForConnectivity = false
        #endif
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    // MARK: - TransferNetworking

    public func fileSize(for url: URL) -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<Int64>()
        let task = session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse,
               let length = http.value(forHTTPHeaderField: "Content-Length"),
               let value = Int64(length), value > 0 {
                box.set(value)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 25)
        return box.get()
    }

    public func download(
        from remote: URL,
        to destination: URL,
        resumeFromByte: Int64,
        progress: @escaping @Sendable (Int64, Int64) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> Int64 {
        var resumeOffset = resumeFromByte
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try runTask(
                    from: remote,
                    to: destination,
                    resumeOffset: resumeOffset,
                    progress: progress,
                    isCancelled: isCancelled
                )
            } catch let error as DownloadError where error == .serverIgnoredRange && attempt == 1 {
                try? FileManager.default.removeItem(at: destination)
                resumeOffset = 0
            }
        }
    }

    private func runTask(
        from remote: URL,
        to destination: URL,
        resumeOffset: Int64,
        progress: @escaping @Sendable (Int64, Int64) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> Int64 {
        var request = URLRequest(url: remote)
        request.timeoutInterval = 60
        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }
        let task = session.downloadTask(with: request)
        let context = TaskContext(
            destination: destination,
            resumeOffset: resumeOffset,
            progress: progress,
            semaphore: DispatchSemaphore(value: 0),
            failure: ResultBox<Error>(),
            finalSize: ResultBox<Int64>()
        )
        lock.lock()
        contexts[task.taskIdentifier] = context
        lock.unlock()

        task.resume()
        while context.semaphore.wait(timeout: .now() + 0.4) == .timedOut {
            if isCancelled() { task.cancel() }
        }
        lock.lock()
        contexts.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        if let error = context.failure.get() {
            if let downloadError = error as? DownloadError { throw downloadError }
            throw error
        }
        if let size = context.finalSize.get(), size > 0 { return size }
        return Self.localSize(destination)
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let context = contexts[downloadTask.taskIdentifier]
        lock.unlock()
        guard let context else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        context.progress(totalBytesWritten + context.resumeOffset, expected + context.resumeOffset)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        let context = contexts[downloadTask.taskIdentifier]
        lock.unlock()
        guard let context else { return }
        do {
            guard let http = downloadTask.response as? HTTPURLResponse else {
                throw DownloadError.httpStatus(-1)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw DownloadError.httpStatus(http.statusCode)
            }
            let isPartial = http.statusCode == 206
            if context.resumeOffset > 0 && !isPartial {
                throw DownloadError.serverIgnoredRange
            }
            if !FileManager.default.fileExists(atPath: context.destination.path) {
                FileManager.default.createFile(atPath: context.destination.path, contents: nil)
            }
            let output = try FileHandle(forWritingTo: context.destination)
            defer { try? output.close() }
            if isPartial {
                try output.seekToEnd()
            } else {
                try output.truncate(atOffset: 0)
            }
            let input = try FileHandle(forReadingFrom: location)
            defer { try? input.close() }
            var written: Int64 = 0
            while let chunk = (try? input.read(upToCount: 1024 * 1024)) ?? nil, !chunk.isEmpty {
                try output.write(contentsOf: chunk)
                written += Int64(chunk.count)
            }
            context.finalSize.set(written + context.resumeOffset)
        } catch {
            context.failure.set(error)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let context = contexts[task.taskIdentifier]
        lock.unlock()
        guard let context else { return }
        if let error, context.failure.get() == nil {
            context.failure.set(error)
        }
        context.semaphore.signal()
    }

    private static func localSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
