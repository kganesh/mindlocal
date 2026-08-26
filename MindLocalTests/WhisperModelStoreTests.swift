import XCTest
@testable import MindLocal

/// The download bookkeeping, minus the download.
///
/// `relativePath` is the part worth pinning: the model folder is recorded
/// relative to the download base because an app container's UUID can change
/// between installs, and an absolute URL saved on one launch may not resolve on
/// the next. Getting this wrong strands 142 MB that `removeDownload` can no
/// longer find.
final class WhisperModelStoreTests: XCTestCase {

    private let base = URL(filePath: "/var/mobile/Containers/Data/Application/ABC/Library/Application Support/WhisperModels")

    func test_relativePath_forFolderInsideBase() {
        let folder = base.appending(path: "models/argmaxinc/whisperkit-coreml/openai_whisper-base.en")
        XCTAssertEqual(WhisperModelStore.relativePath(of: folder, under: base),
                       "models/argmaxinc/whisperkit-coreml/openai_whisper-base.en")
    }

    func test_relativePath_forImmediateChild() {
        XCTAssertEqual(WhisperModelStore.relativePath(of: base.appending(path: "base.en"), under: base),
                       "base.en")
    }

    func test_relativePath_isNilForFolderOutsideBase() {
        // WhisperKit ignoring our downloadBase is the case this guards: usable
        // immediately, but undeletable later, so the store treats it as failure.
        let elsewhere = URL(filePath: "/var/mobile/Containers/Data/Application/ABC/Library/Caches/whisper")
        XCTAssertNil(WhisperModelStore.relativePath(of: elsewhere, under: base))
    }

    func test_relativePath_isNilForTheBaseItself() {
        XCTAssertNil(WhisperModelStore.relativePath(of: base, under: base))
    }

    func test_relativePath_isNilForAParentOfBase() {
        XCTAssertNil(WhisperModelStore.relativePath(of: base.deletingLastPathComponent(), under: base))
    }

    func test_relativePath_rejectsSiblingWithSharedPrefix() {
        // "WhisperModels2" starts with the base's last component as a string
        // but is not inside it — a plain `hasPrefix` on paths would say it is.
        let sibling = base.deletingLastPathComponent().appending(path: "WhisperModels2/base.en")
        XCTAssertNil(WhisperModelStore.relativePath(of: sibling, under: base))
    }

    func test_relativePath_survivesRoundTripThroughADifferentContainer() {
        // The whole point: the same relative path re-resolves under a container
        // whose UUID changed between installs.
        let folder = base.appending(path: "models/openai_whisper-base.en")
        let relative = WhisperModelStore.relativePath(of: folder, under: base)
        let newBase = URL(filePath: "/var/mobile/Containers/Data/Application/XYZ/Library/Application Support/WhisperModels")

        let rebuilt = newBase.appending(path: try! XCTUnwrap(relative))
        XCTAssertEqual(rebuilt.lastPathComponent, "openai_whisper-base.en")
        XCTAssertTrue(rebuilt.path(percentEncoded: false).hasPrefix(newBase.path(percentEncoded: false)))
    }

    func test_relativePath_normalisesTraversal() {
        let messy = base.appending(path: "models/../models/openai_whisper-base.en")
        XCTAssertEqual(WhisperModelStore.relativePath(of: messy, under: base),
                       "models/openai_whisper-base.en")
    }

    // MARK: - Error messages

    func test_message_forOffline_mentionsThatTranscriptionStillWorks() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let message = WhisperModelStore.message(for: offline)
        XCTAssertTrue(message.contains("internet"))
        XCTAssertTrue(message.lowercased().contains("keeps working"))
    }

    func test_message_forOutOfSpace_namesTheSize() {
        let full = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        XCTAssertTrue(WhisperModelStore.message(for: full)
            .contains("\(WhisperModelStore.approximateSizeMB) MB"))
    }

    // MARK: - Engine selection

    func test_engineFallsBackToAppleWhenModelIsMissing() {
        // The preference alone must never select Whisper — a download evicted
        // under storage pressure has to degrade to Apple's recogniser, not to
        // a recorder that refuses to record.
        let original = SpeechEngine.useWhisper
        defer { SpeechEngine.useWhisper = original }

        SpeechEngine.useWhisper = true
        WhisperModelStore.shared.removeDownload()

        XCTAssertFalse(SpeechEngine.isWhisperActive)
        XCTAssertTrue(SpeechEngine.make() is SpeechService)
    }
}
