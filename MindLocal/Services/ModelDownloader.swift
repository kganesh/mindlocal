import Foundation

enum ModelDownloadError: Error {
    case httpStatus(Int)
    case incomplete
}

/// Downloads one large file to disk, reporting progress.
///
/// Exists because the ergonomic API is wrong for this job: `URLSession.bytes`
/// vends an `AsyncSequence` of individual `UInt8`, so a 327 MB model becomes
/// hundreds of millions of `await`s — and on a `MainActor`-isolated caller,
/// hundreds of millions of main-actor hops. `URLSessionDownloadTask` writes to
/// a temp file on its own thread instead, and only progress crosses back.
///
/// `nonisolated` and `@unchecked Sendable`: URLSession calls its delegate on a
/// background queue, and the continuation is only ever touched from that queue
/// (the delegate methods used here are mutually exclusive per task).
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @Sendable (Double) -> Void
    private var session: URLSession?

    private init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
        super.init()
    }

    /// Returns a URL in the temporary directory that the caller owns and must
    /// move or delete.
    static func download(from url: URL,
                         onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let downloader = ModelDownloader(onProgress: onProgress)
        return try await downloader.run(url: url)
    }

    private func run(url: URL) async throws -> URL {
        let configuration = URLSessionConfiguration.default
        // The default 7-day resource timeout is fine, but the 60-second
        // request timeout applies between packets on a slow link.
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 3600
        configuration.waitsForConnectivity = true

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        defer { session.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // URLSession deletes `location` the moment this method returns, so the
        // file has to be moved here, synchronously — not in a Task.
        guard let continuation else { return }
        self.continuation = nil

        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            continuation.resume(throwing: ModelDownloadError.httpStatus(http.statusCode))
            return
        }

        let staged = FileManager.default.temporaryDirectory
            .appending(path: "model-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: staged)
            continuation.resume(returning: staged)
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        // Fires after didFinishDownloadingTo on success, where the continuation
        // has already been consumed and nilled.
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error ?? ModelDownloadError.incomplete)
    }
}
