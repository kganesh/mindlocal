import Foundation

/// Owns the on-demand Kokoro weights download.
///
/// The voices ship in the app (`voices.npz`, 14 MB) so the picker works before
/// anything is downloaded; the 327 MB model does not. Until it arrives — and
/// any time it goes missing — read-aloud falls back to `AVSpeechSynthesizer`.
///
/// Deliberately parallel to `WhisperModelStore`, down to the relative-path
/// bookkeeping, because the two solve the same problem. The ~15 duplicated
/// lines are left duplicated rather than hoisted into a shared base: the
/// download mechanics differ (WhisperKit ships its own downloader, this is a
/// plain URLSession) and merging them would couple transcription to playback
/// for no real gain.
@Observable
final class KokoroModelStore {

    static let shared = KokoroModelStore()

    enum State: Equatable {
        case unavailable
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .notDownloaded
    private(set) var modelFile: URL?

    /// MLX-format weights. Despite the repo's `-bf16` name the file is 327 MB,
    /// the same size as the fp32 original — the tensors are not actually
    /// halved. Kept because it is the widely-used MLX mirror and the filename
    /// matches what `KokoroTTS` expects; revisit if a real fp16 export appears.
    static let modelURL = URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/kokoro-v1_0.safetensors")!

    static let approximateSizeMB = 327
    static let fileName = "kokoro-v1_0.safetensors"
    private static let relativePathKey = "kokoro.model.relativePath"

    static var downloadBase: URL {
        URL.applicationSupportDirectory.appending(path: "KokoroModel", directoryHint: .isDirectory)
    }

    private var downloadTask: Task<Void, Never>?

    init() { resolveFromDisk() }

    // MARK: - Lifecycle

    private func resolveFromDisk() {
        #if canImport(KokoroSwift)
        guard let relative = UserDefaults.standard.string(forKey: Self.relativePathKey) else {
            state = .notDownloaded
            return
        }
        let file = Self.downloadBase.appending(path: relative)
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            modelFile = file
            state = .ready
        } else {
            UserDefaults.standard.removeObject(forKey: Self.relativePathKey)
            state = .notDownloaded
        }
        #else
        state = .unavailable
        #endif
    }

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    // MARK: - Download

    func download() async {
        #if canImport(KokoroSwift)
        guard !isDownloading, state != .ready else { return }
        state = .downloading(progress: 0)

        do {
            try FileManager.default.createDirectory(at: Self.downloadBase,
                                                    withIntermediateDirectories: true)
            let destination = Self.downloadBase.appending(path: Self.fileName)

            // Streamed to disk rather than `URLSession.data(from:)` — 327 MB
            // held in memory would be jetsammed on a phone.
            let (bytes, response) = try await URLSession.shared.bytes(from: Self.modelURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                state = .failed("The download server returned an error.")
                return
            }
            let expected = response.expectedContentLength

            FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }

            var buffer = Data()
            buffer.reserveCapacity(1 << 20)
            var written: Int64 = 0

            for try await byte in bytes {
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: destination)
                    state = .notDownloaded
                    return
                }
                buffer.append(byte)
                if buffer.count >= (1 << 20) {
                    try handle.write(contentsOf: buffer)
                    written += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expected > 0 {
                        state = .downloading(progress: Double(written) / Double(expected))
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
            }

            guard expected <= 0 || written == expected else {
                try? FileManager.default.removeItem(at: destination)
                state = .failed("The download ended early. Try again on a stable connection.")
                return
            }

            UserDefaults.standard.set(Self.fileName, forKey: Self.relativePathKey)
            modelFile = destination
            state = .ready
        } catch {
            state = .failed(Self.message(for: error))
        }
        #else
        state = .unavailable
        #endif
    }

    func removeDownload() {
        if let modelFile { try? FileManager.default.removeItem(at: modelFile) }
        UserDefaults.standard.removeObject(forKey: Self.relativePathKey)
        modelFile = nil
        #if canImport(KokoroSwift)
        state = .notDownloaded
        #else
        state = .unavailable
        #endif
    }

    // MARK: - Helpers

    static func message(for error: Error) -> String {
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet):
            return "No internet connection. Read-aloud keeps working with the built-in voice."
        case (NSURLErrorDomain, NSURLErrorTimedOut):
            return "The download timed out. Try again on a stronger connection."
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError):
            return "Not enough storage for the \(approximateSizeMB) MB voice model."
        default:
            return "The download didn't finish. \(nsError.localizedDescription)"
        }
    }
}
