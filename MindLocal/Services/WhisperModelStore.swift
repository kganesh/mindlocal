import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

/// Owns the on-demand Whisper model download.
///
/// The weights are ~142 MB, so they aren't bundled — the app ships with Apple's
/// on-device transcription working, and Whisper becomes available only after
/// the user turns it on in Settings and accepts the download. Everything here
/// is about that one file: whether it's present, fetching it, and giving it
/// back so it can be deleted.
///
/// Nothing here makes MindLocal less private: the download pulls model weights
/// down from Argmax's Hugging Face repo. No journal content is uploaded, and
/// transcription still runs entirely on-device once the weights are in place.
@Observable
final class WhisperModelStore {

    static let shared = WhisperModelStore()

    enum State: Equatable {
        /// WhisperKit isn't linked into this build.
        case unavailable
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .notDownloaded

    /// Folder the model was unpacked into, once `state` is `.ready`.
    private(set) var modelFolder: URL?

    /// WhisperKit model identifier. `.en` beats multilingual `base` on English;
    /// changing this must also clear any existing download, since the stored
    /// path points at the old variant's folder.
    static let variant = "base.en"

    /// Shown in the download prompt. Approximate on purpose — the exact figure
    /// depends on which files the variant ships.
    static let approximateSizeMB = 142

    private static let relativePathKey = "whisper.model.relativePath"

    /// Where downloads land. Chosen rather than left to WhisperKit's default so
    /// the location is stable and `removeDownload` knows what to delete.
    static var downloadBase: URL {
        URL.applicationSupportDirectory.appending(path: "WhisperModels", directoryHint: .isDirectory)
    }

    init() {
        resolveFromDisk()
    }

    // MARK: - Lifecycle

    /// Re-establishes state at launch.
    ///
    /// The stored path is relative, not absolute: an app container's UUID can
    /// change between installs, so an absolute URL saved on one launch may not
    /// resolve on the next. Rebuilding from `downloadBase` survives that.
    private func resolveFromDisk() {
        #if canImport(WhisperKit)
        guard let relative = UserDefaults.standard.string(forKey: Self.relativePathKey) else {
            state = .notDownloaded
            return
        }
        let folder = Self.downloadBase.appending(path: relative, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            modelFolder = folder
            state = .ready
        } else {
            // Deleted by the system under storage pressure, or left behind by a
            // failed unpack. Forget it and offer the download again.
            UserDefaults.standard.removeObject(forKey: Self.relativePathKey)
            state = .notDownloaded
        }
        #else
        state = .unavailable
        #endif
    }

    // MARK: - Download

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    func download() async {
        #if canImport(WhisperKit)
        guard !isDownloading, state != .ready else { return }
        state = .downloading(progress: 0)

        do {
            try FileManager.default.createDirectory(at: Self.downloadBase,
                                                    withIntermediateDirectories: true)

            let folder = try await WhisperKit.download(
                variant: Self.variant,
                downloadBase: Self.downloadBase,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.isDownloading else { return }
                        self.state = .downloading(progress: progress.fractionCompleted)
                    }
                }
            )

            guard let relative = Self.relativePath(of: folder, under: Self.downloadBase) else {
                // WhisperKit put the model somewhere outside the base we gave
                // it. Usable now, but `removeDownload` couldn't find it later,
                // so treat it as a failure rather than strand 142 MB.
                state = .failed("The model was saved to an unexpected location.")
                return
            }

            UserDefaults.standard.set(relative, forKey: Self.relativePathKey)
            modelFolder = folder
            state = .ready
        } catch {
            state = .failed(Self.message(for: error))
        }
        #else
        state = .unavailable
        #endif
    }

    /// Deletes the weights and reverts to Apple's transcription.
    func removeDownload() {
        if let modelFolder {
            try? FileManager.default.removeItem(at: modelFolder)
        }
        UserDefaults.standard.removeObject(forKey: Self.relativePathKey)
        modelFolder = nil
        #if canImport(WhisperKit)
        state = .notDownloaded
        #else
        state = .unavailable
        #endif
    }

    // MARK: - Helpers

    /// Path of `folder` relative to `base`, or nil when it isn't inside it.
    ///
    /// Pure string work over path components so it can be tested without
    /// touching the filesystem; callers pass already-standardized URLs.
    static func relativePath(of folder: URL, under base: URL) -> String? {
        let folderParts = folder.standardizedFileURL.pathComponents
        let baseParts = base.standardizedFileURL.pathComponents
        guard folderParts.count > baseParts.count,
              Array(folderParts.prefix(baseParts.count)) == baseParts
        else { return nil }
        return folderParts.dropFirst(baseParts.count).joined(separator: "/")
    }

    static func message(for error: Error) -> String {
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet):
            return "No internet connection. The download needs one; transcription keeps working without it."
        case (NSURLErrorDomain, NSURLErrorTimedOut):
            return "The download timed out. Try again on a stronger connection."
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError):
            return "Not enough storage for the \(approximateSizeMB) MB model."
        default:
            return "The download didn't finish. \(nsError.localizedDescription)"
        }
    }
}
