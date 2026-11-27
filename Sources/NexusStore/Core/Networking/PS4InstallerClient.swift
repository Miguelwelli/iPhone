import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the PS4 web package installer (the "install package" endpoint exposed by the console's
/// local web toolkit on port 12800).
///
/// Endpoint used by homebrew package managers: `POST http://<console>:12800/upload`
/// with `multipart/form-data` field `file` containing the `.pkg`.
///
/// Important honesty notes:
/// - Requires the console to be in an environment that exposes this endpoint (a user-managed
///   configuration). This app does not enable it, bypass it or claim it exists by default.
/// - Plain HTTP **is** allowed for this specific host: the app declares a narrow ATS exception for
///   local-network HTTP (see `Info.plist` / `Docs/PS4-SETUP.md`).
/// - On success the console answers 200 with a small JSON body; failures surface the raw response so
///   the user can see exactly why it was rejected.
public final class PS4InstallerClient: @unchecked Sendable {

    public struct Result: Sendable {
        public var statusCode: Int
        public var body: String
        public var succeeded: Bool
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Uploads `fileURL` with a streaming multipart body.
    @discardableResult
    public func upload(
        fileURL: URL,
        to host: String,
        port: UInt16 = 12800,
        fileName: String? = nil,
        progress: ((Int64, Int64) -> Void)? = nil,
        isCancelled: () -> Bool = { false }
    ) throws -> Result {
        guard let url = URL(string: "http://\(host):\(port)/upload") else {
            throw SendError.invalidURL("http://\(host):\(port)/upload")
        }
        let name = fileName ?? fileURL.lastPathComponent
        let boundary = "nexusstore-" + UUID().uuidString
        guard let bodyURL = Self.makeMultipartFile(
            fileURL: fileURL,
            fileName: name,
            boundary: boundary,
            progress: progress,
            isCancelled: isCancelled
        ) else {
            throw SendError.uploadFailed("não foi possível montar o corpo multipart")
        }
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 * 60

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox<Result>()
        let failureBox = ResultBox<Error>()

        let task = session.uploadTask(with: request, fromFile: bodyURL) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                failureBox.set(SendError.uploadFailed(error.localizedDescription))
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            resultBox.set(Result(statusCode: code, body: body, succeeded: (200..<300).contains(code)))
        }
        task.resume()
        while semaphore.wait(timeout: .now() + 0.5) == .timedOut {
            if isCancelled() {
                task.cancel()
                throw SendError.cancelled
            }
        }
        if let failure = failureBox.get() { throw failure }
        guard let outcome = resultBox.get() else { throw SendError.cancelled }
        guard outcome.succeeded else {
            throw SendError.installerRejected(status: outcome.statusCode, body: outcome.body)
        }
        return outcome
    }

    /// Builds the multipart body on disk (avoids holding a multi-GB package in RAM).
    public static func makeMultipartFile(
        fileURL: URL,
        fileName: String,
        boundary: String,
        progress: ((Int64, Int64) -> Void)?,
        isCancelled: () -> Bool
    ) -> URL? {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexusstore-multipart-\(UUID().uuidString).dat")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let outHandle = try? FileHandle(forWritingTo: output),
              let inHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer {
            try? outHandle.close()
            try? inHandle.close()
        }
        let total = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.int64Value ?? 0
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: application/octet-stream\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else { return nil }
        try? outHandle.write(contentsOf: headerData)

        var written: Int64 = 0
        while true {
            if isCancelled() { try? FileManager.default.removeItem(at: output); return nil }
            let chunk = (try? inHandle.read(upToCount: 256 * 1024)) ?? nil
            guard let chunk, !chunk.isEmpty else { break }
            try? outHandle.write(contentsOf: chunk)
            written += Int64(chunk.count)
            progress?(written, total)
        }
        let footer = "\r\n--\(boundary)--\r\n"
        if let footerData = footer.data(using: .utf8) {
            try? outHandle.write(contentsOf: footerData)
        }
        return output
    }
}
