import Foundation
import FoundationModels
import OSLog

/// Routes a generation through Private Cloud Compute when it is available, and
/// falls back to the on-device model when PCC cannot serve the request.
///
/// The fallback is not a safety net, it is the reason this compiles into a
/// working app. Both `ExtractionService` and `AdviceService` construct their
/// `SystemLanguageModel` with `.permissiveContentTransformations`, because the
/// default guardrails refuse ordinary journal content and — see the comment on
/// `AdviceService.answerModel` — refuse questions that name real people, which
/// is this app's primary query shape. `PrivateCloudComputeLanguageModel` has a
/// single zero-argument initialiser and exposes no guardrails setting at all,
/// so whatever policy it runs is not ours to relax. A refusal therefore has to
/// land somewhere, and it lands on the on-device model, which still carries the
/// permissive configuration.
///
/// Whether PCC actually refuses this content is unmeasured: the absent
/// guardrails parameter is an API fact, the refusal rate is an inference. If it
/// refuses often, the Advise path pays PCC latency and then answers on-device
/// anyway, and routing Advise to PCC stops being worth it. Measure on a device
/// before trusting the arrangement.
enum ModelRouter {

    /// Flip to `true` in the same change that adds
    /// `com.apple.developer.private-cloud-compute` to `MindLocal.entitlements`.
    /// These two move together — always.
    ///
    /// Why a build-time switch rather than a runtime probe: PCC does not fail
    /// gracefully on an unentitled app, it traps the process —
    ///
    ///     FoundationModels/ErrorConversion.swift:140: Fatal error:
    ///     Missing entitlement: com.apple.developer.private-cloud-compute
    ///
    /// That is SIGTRAP, so no `do`/`catch` intercepts it, and `isAvailable` is
    /// itself the crash, so the framework cannot be asked whether PCC is usable.
    /// iOS offers no way to read your own entitlements at runtime either
    /// (`SecTaskCopyValueForEntitlement` is macOS-only). So this constant is the
    /// gate, and while it is `false` the app runs on-device exactly as it did
    /// before PCC existed.
    ///
    /// Getting the pair wrong in one direction is harmless (entitlement present,
    /// flag `false` — PCC simply unused); in the other it crashes on first use.
    private static let privateCloudComputeEnabled = true

    private static let log = Logger(subsystem: "com.gayatrikolekar.MindLocal", category: "ModelRouter")

    /// Which engine served the most recent generation. Purely observational —
    /// without it there is no way to tell PCC from on-device at runtime, which
    /// makes every "is PCC actually being used?" question unanswerable and every
    /// A/B impression unfalsifiable.
    enum Engine: String, Sendable {
        case privateCloudCompute = "PCC"
        case onDevice = "on-device"
        case onDeviceAfterPCCRefusal = "on-device (PCC declined)"
    }

    private(set) nonisolated(unsafe) static var lastEngine: Engine?

    
    /// Appends one line to `Documents/engine-log.txt`.
    ///
    /// A console session (`devicectl … --console`) proved unusable for this:
    /// `os.Logger` goes to the unified log rather than stdout, `print` to a pipe
    /// is block-buffered so lines are lost when the process exits, and the
    /// session detaches the moment the app leaves the foreground. A file
    /// survives all three, and can be pulled later with
    /// `devicectl device copy from --domain-type appDataContainer`.
    ///
    /// Debug builds only. It is diagnostic instrumentation, and a release that
    /// grows a file in the app container forever — into every device backup —
    /// is not something a tester signed up for. The call sites stay; this
    /// becomes nothing.
    static func record(_ line: @autoclosure () -> String) {
        #if !DEBUG
        return
        #else
        let line = line()
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp)  \(line)\n"
        guard let dir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("engine-log.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: url)
        }
        #endif
    }

    /// Writes one synthesized chunk to `Documents` as a WAV, for listening to
    /// and measuring off the device. Debug only, like `record`.
    ///
    /// Reading a waveform is the only way to tell the two candidate causes of
    /// the read-aloud static apart: noise inside the samples means the model
    /// produced it, and silence means playback starved. Guessing between those
    /// from a description has not worked.
    static func dumpAudio(_ samples: [Float], sampleRate: Double, label: String) {
        #if !DEBUG
        return
        #else
        guard let dir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first else { return }
        let slug = label.prefix(40)
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
        let url = dir.appendingPathComponent("chunk-\(Int(Date().timeIntervalSince1970))-\(slug).wav")

        let rate = UInt32(sampleRate)
        let byteCount = UInt32(samples.count * 2)
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))              // PCM header size
        append(UInt16(1))               // PCM
        append(UInt16(1))               // mono
        append(rate)
        append(rate * 2)                // byte rate
        append(UInt16(2))               // block align
        append(UInt16(16))              // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(byteCount)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * 32767))
        }
        try? data.write(to: url)
        #endif
    }

    /// Whether PCC can serve this device and OS right now. Mirrors
    /// `SystemLanguageModel.isAvailable` so callers can treat the two alike.
    static var isPrivateCloudComputeAvailable: Bool {
        guard privateCloudComputeEnabled else { return false }
        if #available(iOS 27.0, *) {
            return PrivateCloudComputeLanguageModel().isAvailable
        }
        return false
    }

    /// The context window of the engine that will actually serve the next
    /// request — PCC's when PCC is in play, the on-device model's otherwise.
    ///
    /// Caveat worth knowing before trusting a large budget: if PCC declines a
    /// request, `withSession` retries on-device, and context sized for PCC's
    /// window will not fit the on-device one. `exceededContextWindowSize` is
    /// deliberately not in the retry set, so that surfaces as an error rather
    /// than a silent truncation. Measured behaviour so far is zero declines, but
    /// this is the failure mode to look for if one ever appears in the log.
    static func effectiveContextSize(onDevice: SystemLanguageModel) async -> Int {
        if #available(iOS 27.0, *), privateCloudComputeEnabled {
            let pcc = PrivateCloudComputeLanguageModel()
            if pcc.isAvailable, let size = try? await pcc.contextSize {
                return size
            }
        }
        return onDevice.contextSize
    }

    /// Runs `body` against PCC when possible, otherwise against `onDevice`.
    ///
    /// `body` receives the session rather than this returning one, so a PCC
    /// refusal can be retried on a fresh on-device session — a session cannot
    /// change models after the fact.
    static func withSession<T>(
        instructions: String,
        onDevice: SystemLanguageModel,
        _ body: (LanguageModelSession) async throws -> T
    ) async throws -> T {
        var pccDeclined = false
        if #available(iOS 27.0, *), privateCloudComputeEnabled {
            let pcc = PrivateCloudComputeLanguageModel()
            if pcc.isAvailable {
                do {
                    let value = try await body(
                        LanguageModelSession(model: pcc, instructions: instructions)
                    )
                    lastEngine = .privateCloudCompute
                    log.info("served by Private Cloud Compute")
                    record("served by Private Cloud Compute")
                    return value
                } catch {
                    guard fallsBackToDevice(error) else {
                        log.error("PCC failed, not retryable: \(String(describing: error), privacy: .public)")
                        record("PCC failed, not retryable: \(error)")
                        throw error
                    }
                    log.info("PCC declined, falling back on-device: \(String(describing: error), privacy: .public)")
                    record("PCC declined, falling back on-device: \(error)")
                    pccDeclined = true
                }
            }
        }
        let value = try await body(
            LanguageModelSession(model: onDevice, instructions: instructions)
        )
        lastEngine = pccDeclined ? .onDeviceAfterPCCRefusal : .onDevice
        log.info("served \(lastEngine?.rawValue ?? "?", privacy: .public)")
        record("served \(lastEngine?.rawValue ?? "?")")
        return value
    }

    /// Distinguishes "PCC could not serve this" from "this request is broken".
    ///
    /// Only the former is worth retrying. A `decodingFailure` or an
    /// `unsupportedGuide` is a property of the prompt and would fail identically
    /// on either model, and `exceededContextWindowSize` against PCC's larger
    /// window is guaranteed to exceed the on-device one too — retrying those
    /// just turns one error into the same error, more slowly.
    private static func fallsBackToDevice(_ error: Error) -> Bool {
        // There are TWO error enums, and PCC throws the other one.
        // LanguageModelSession.GenerationError and LanguageModelError both carry
        // .guardrailViolation and .refusal, and handling only the first meant a
        // real PCC refusal — "Response may contain sensitive or unsafe content"
        // on the entirely benign question "what is the next event I should be
        // looking forward to?" — was classed as not retryable and surfaced to the
        // user as an error, instead of retrying on-device where
        // .permissiveContentTransformations would very likely have answered it.
        // The fallback existed for exactly this case and never fired.
        if #available(iOS 27.0, *), let modelError = error as? LanguageModelError {
            switch modelError {
            case .guardrailViolation, .refusal, .rateLimited, .timeout:
                return true
            default:
                // .contextSizeExceeded deliberately excluded: a prompt too large
                // for PCC's window cannot fit the on-device one either.
                return false
            }
        }
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .guardrailViolation, .refusal, .rateLimited, .concurrentRequests:
                return true
            default:
                return false
            }
        }
        // Network failure, exhausted daily quota, service unavailable. A journal
        // that stopped extracting whenever the network dropped would be worse
        // than one that never reached for PCC.
        if #available(iOS 27.0, *), error is PrivateCloudComputeLanguageModel.Error {
            return true
        }
        return false
    }
}

/// A drop-in stand-in for `LanguageModelSession` that routes through
/// `ModelRouter`.
///
/// It exists so adopting PCC did not mean rewriting nine call sites into
/// closures. Each site still reads `let session = …` then `session.respond(…)`;
/// only the construction line changed. The `respond` overloads mirror the two
/// shapes this app actually uses.
///
/// One consequence worth knowing: because a refusal is retried on a *fresh*
/// on-device session, this type is only equivalent to `LanguageModelSession`
/// for single-shot requests. Every call site here is single-shot. If anything
/// ever needs multi-turn transcript continuity, it must hold a real
/// `LanguageModelSession` instead — a retry would silently lose the transcript.
struct RoutedSession {
    private let instructions: String
    private let onDevice: SystemLanguageModel

    init(instructions: String, onDevice: SystemLanguageModel) {
        self.instructions = instructions
        self.onDevice = onDevice
    }

    func respond(
        to prompt: String,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> LanguageModelSession.Response<String> {
        try await ModelRouter.withSession(instructions: instructions, onDevice: onDevice) {
            try await $0.respond(to: prompt, options: options)
        }
    }

    func respond<Content: Generable>(
        to prompt: String,
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> LanguageModelSession.Response<Content> {
        try await ModelRouter.withSession(instructions: instructions, onDevice: onDevice) {
            try await $0.respond(
                to: prompt,
                generating: type,
                includeSchemaInPrompt: includeSchemaInPrompt,
                options: options
            )
        }
    }
}
