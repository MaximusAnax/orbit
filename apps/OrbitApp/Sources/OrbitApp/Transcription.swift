import Foundation
import OrbitPipeline

/// On-device transcription (DATA-MODEL §6). Audio NEVER leaves the device (PRIV-1)
/// — this protocol has no network implementation and never will; the only
/// content-carrying egress in the app is the extraction endpoint (PRIV-2).
protocol TranscriptionService: Sendable {
    func transcribe(audioAt path: String, primedWith names: [String]) async throws -> TranscriptResult
}

struct TranscriptResult: Sendable {
    var text: String
    /// §7.5/§6 gate: audio may be deleted only when this is true. A tiny-model
    /// transcript is not good enough to be the permanent and only record.
    var usedFullModel: Bool
    var lowConfidenceTokenRanges: [Range<Int>] = []
}

/// Bundle a floor, download the ceiling (§6): `base` ships in the app so capture
/// never hard-fails; `large-v3-turbo` (quantized) downloads during onboarding and
/// can upgrade without an app release.
final class ModelManager: @unchecked Sendable {
    enum Tier: String { case floor = "ggml-base-q5_1", ceiling = "ggml-large-v3-turbo-q5_0" }

    var ceilingURL: URL? {
        let url = modelsDirectory.appendingPathComponent(Tier.ceiling.rawValue + ".bin")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var floorURL: URL? {
        Bundle.main.url(forResource: Tier.floor.rawValue, withExtension: "bin")
    }
    var modelsDirectory: URL {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true))?
            .appendingPathComponent("models") ?? URL(fileURLWithPath: "/tmp/models")
    }

    /// Same artifact scripts/build-whisper.sh fetches for the Mac.
    static let ceilingDownloadURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!

    /// Onboarding has dead time (permissions, first portraits) — that's when
    /// this runs. Failure leaves the floor model doing honest work with audio
    /// retained (§7.5); retried on next launch. PRIV note: this is an inbound
    /// fetch of a public artifact — no user content leaves the device (PRIV-2
    /// governs content-carrying egress; this carries none).
    func downloadCeilingIfNeeded() async {
        guard ceilingURL == nil else { return }
        do {
            let (tmp, response) = try await URLSession.shared.download(from: Self.ceilingDownloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            try FileManager.default.createDirectory(at: modelsDirectory,
                                                    withIntermediateDirectories: true)
            let dest = modelsDirectory.appendingPathComponent(Tier.ceiling.rawValue + ".bin")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            // quiet: the floor model keeps capture working (P3); no nagging (P10)
        }
    }
}

/// whisper.cpp wrapper. Decode discipline per the 2026-07-27 empirical findings:
/// context carryover OFF (`-mc 0` equivalent — primed runs loop on disfluent
/// speech otherwise), entropy-threshold tuned, prompt primed with known names as
/// an assist; the NameMatcher post-pass is the correctness mechanism (PIPE-1).
final class WhisperTranscriber: TranscriptionService, @unchecked Sendable {
    let models: ModelManager

    init(models: ModelManager) {
        self.models = models
    }

    func transcribe(audioAt path: String, primedWith names: [String]) async throws -> TranscriptResult {
        let (modelURL, isFull): (URL?, Bool) = models.ceilingURL.map { ($0, true) }
            ?? (models.floorURL, false)
        guard let modelURL else {
            throw TranscriptionError.noModel
        }
        // WhisperBridge is the C-interop target produced by scripts/build-whisper.sh
        // (whisper.xcframework). Parameters set there: no_context=true, entropy_thold
        // tuned, initial_prompt = names.joined — see the script for the exact flags.
        let text = try await WhisperBridge.run(
            model: modelURL, audio: URL(fileURLWithPath: path),
            initialPrompt: names.prefix(48).joined(separator: ", "))
        return TranscriptResult(text: text, usedFullModel: isFull)
    }
}

enum TranscriptionError: Error {
    case noModel
    case bridgeUnavailable
    /// Speech-recognition permission not granted (the user can fix this).
    case speechDenied
    /// The recognizer exists but cannot run **on device** — refused rather than
    /// silently sending the recording to a server (PRIV-1 is absolute).
    case onDeviceUnavailable
    /// The recognizer ran and heard no speech. The phone is fine; the recording
    /// is the problem — the opposite diagnosis from `onDeviceUnavailable`, so it
    /// must never share a line with it.
    case noSpeechFound
    /// The audio file itself could not be opened or decoded — empty, truncated,
    /// or otherwise not playable. Nothing about the phone or the recognizer is
    /// wrong, and no retry will help, so this must not be worded as "not yet".
    case audioUnreadable
    /// Anything else the recognizer reported, carrying its reason so a failure
    /// is diagnosable instead of a shrug (same discipline as
    /// `RecordingError.sessionFailed`).
    case recognizerFailed(String)
}

/// Tries each transcriber in order and returns the first success; the last
/// error survives if every stage fails. Order is quality-first: whisper's
/// ceiling model when it's on the phone, Apple's on-device recognizer as the
/// floor that keeps capture working the moment the app is installed.
final class CascadingTranscriber: TranscriptionService, @unchecked Sendable {
    private let stages: [TranscriptionService]
    init(_ stages: [TranscriptionService]) { self.stages = stages }

    func transcribe(audioAt path: String, primedWith names: [String]) async throws -> TranscriptResult {
        var last: Error = TranscriptionError.noModel
        for stage in stages {
            do { return try await stage.transcribe(audioAt: path, primedWith: names) }
            catch { last = error }
        }
        throw last
    }
}

/// Resume-once guard for callback APIs that may fire more than once.
private final class OnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

#if canImport(Speech) && os(iOS)
import Speech
import AVFoundation      // AVFoundationErrorDomain, for classify(_:)

/// Apple's on-device recognizer as the transcription floor (DATA-MODEL §6
/// ratified `SpeechTranscriber` on iOS 26 for this role; this is the same idea
/// on the iOS 17 API, registered as a divergence in RATIFICATION §4.12).
///
/// **PRIV-1 is absolute here.** `requiresOnDeviceRecognition = true` is set and
/// `supportsOnDeviceRecognition` is checked first: if this phone cannot
/// recognize locally, transcription fails rather than putting the recording on
/// Apple's servers. There is deliberately no server-side path to fall into.
///
/// Results report `usedFullModel: false`, so §7.5 keeps the audio until
/// whisper's ceiling model re-listens — the upgrade pass then replaces this
/// transcript with the better one and deletes the recording.
final class AppleSpeechTranscriber: TranscriptionService, @unchecked Sendable {
    func transcribe(audioAt path: String, primedWith names: [String]) async throws -> TranscriptResult {
        guard await Self.authorized() else { throw TranscriptionError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriptionError.onDeviceUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
        request.requiresOnDeviceRecognition = true      // never negotiable
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        // the same name-priming discipline whisper gets via initial_prompt
        request.contextualStrings = Array(names.prefix(48))

        // The delegate form, not the result-handler form, on purpose: the handler
        // is only called when there is something to report, so a task that ends
        // without either a final result or an error leaves the continuation
        // dangling and parks the UI in `.transcribing` forever. The delegate's
        // `didFinishSuccessfully` always fires, so RecognitionSink can guarantee
        // exactly one resume — a failure the user can read beats a silent hang.
        let text: String = try await withCheckedThrowingContinuation { continuation in
            let sink = RecognitionSink(continuation: continuation)
            sink.task = recognizer.recognitionTask(with: request, delegate: sink)
        }
        return TranscriptResult(text: text, usedFullModel: false)
    }

    /// Speech reports failures as opaque `kAFAssistantErrorDomain` codes. Two of
    /// them mean opposite things and were previously indistinguishable at the
    /// call site: 1110 is "this audio held no speech" (recording problem), 1101
    /// is "local recognition couldn't start" (phone problem — usually the
    /// on-device language asset isn't installed). Everything else keeps its
    /// domain and code so it can be looked up rather than guessed at.
    fileprivate static func classify(_ error: Error) -> TranscriptionError {
        let ns = error as NSError
        // An AVFoundation error here is the recognizer reporting that it could
        // not open the file we handed it (-11800 AVErrorUnknown is the usual
        // shape for an empty or truncated capture). That is a fact about the
        // recording, not about this phone's ability to transcribe — the two
        // must not share a line, because one is retryable and the other never is.
        if ns.domain == AVFoundationErrorDomain { return .audioUnreadable }
        guard ns.domain == "kAFAssistantErrorDomain" else {
            return .recognizerFailed("\(ns.domain) \(ns.code)")
        }
        switch ns.code {
        case 1110: return .noSpeechFound
        case 1101: return .onDeviceUnavailable
        default: return .recognizerFailed("\(ns.domain) \(ns.code)")
        }
    }

    private static func authorized() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }
}

/// Bridges `SFSpeechRecognitionTaskDelegate` to one checked continuation.
///
/// Two lifetime facts drive the shape of this: the recognizer holds its delegate
/// weakly, and it does not keep the task alive for the caller — so the sink
/// retains itself and its task, and drops both the moment it resumes. Without
/// that, the sink deallocates the instant `transcribe` suspends and no callback
/// ever arrives.
private final class RecognitionSink: NSObject, SFSpeechRecognitionTaskDelegate, @unchecked Sendable {
    private let continuation: CheckedContinuation<String, Error>
    private let once = OnceBox()
    var task: SFSpeechRecognitionTask?
    private var selfRetain: RecognitionSink?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
        super.init()
        selfRetain = self          // released in finish(), below
    }

    private func finish(_ result: Result<String, Error>) {
        guard once.claim() else { return }
        continuation.resume(with: result)
        task = nil
        selfRetain = nil
    }

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask,
                               didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        finish(.success(recognitionResult.bestTranscription.formattedString))
    }

    /// Always called when the task ends, success or not. If a transcript already
    /// arrived this is a no-op; if nothing did, this is the arm that keeps the
    /// caller from waiting forever.
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        finish(.failure(task.error.map(AppleSpeechTranscriber.classify)
            ?? TranscriptionError.recognizerFailed("the recognizer ended without a transcript")))
    }
}
#endif

/// Mic failures the capture door has to tell the truth about. `denied` is the
/// one the user can fix (Settings › Orbit › Microphone); `sessionFailed`
/// carries the underlying reason so a failure is diagnosable instead of a
/// shrug — the typed note stays available either way (P3).
enum RecordingError: Error {
    case denied
    case sessionFailed(String)
    case didNotStart
}

#if canImport(whisper)
import whisper
import AVFoundation

/// The whisper.cpp C bridge. Active once scripts/build-whisper.sh has produced
/// Vendor/whisper.xcframework and it's added to project.yml (the script prints
/// the exact lines). Decode discipline per the 2026-07-27 empirical findings:
/// context carryover OFF, entropy threshold 2.8, greedy at temperature 0,
/// names primed via initial_prompt (assist only — NameMatcher is the
/// correctness mechanism, PIPE-1).
enum WhisperBridge {
    static func run(model: URL, audio: URL, initialPrompt: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let samples = try decodePCM16kMono(audio)
            let cparams = whisper_context_default_params()
            guard let ctx = whisper_init_from_file_with_params(model.path, cparams) else {
                throw TranscriptionError.bridgeUnavailable
            }
            defer { whisper_free(ctx) }

            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.no_context = true          // -mc 0: primed runs loop on disfluency otherwise
            params.entropy_thold = 2.8
            params.temperature = 0
            params.print_progress = false
            params.print_realtime = false
            params.n_threads = Int32(max(2, min(6, ProcessInfo.processInfo.processorCount - 1)))

            let prompt = strdup(initialPrompt)
            defer { free(prompt) }
            params.initial_prompt = UnsafePointer(prompt)

            let rc = samples.withUnsafeBufferPointer { buffer in
                whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
            }
            guard rc == 0 else { throw TranscriptionError.bridgeUnavailable }

            var text = ""
            for i in 0..<whisper_full_n_segments(ctx) {
                if let segment = whisper_full_get_segment_text(ctx, i) {
                    text += String(cString: segment)
                }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    /// AAC m4a (DeviceRecorder's output) → 16 kHz mono Float32 PCM, whisper's
    /// required input. AVFoundation decodes; no audio leaves the process.
    static func decodePCM16kMono(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw TranscriptionError.bridgeUnavailable
        }
        var samples: [Float] = []
        let inCapacity: AVAudioFrameCount = 8192
        var reachedEnd = false
        while !reachedEnd {
            let outCapacity = AVAudioFrameCount(
                Double(inCapacity) * target.sampleRate / file.processingFormat.sampleRate) + 64
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target,
                                                   frameCapacity: outCapacity) else { break }
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
                guard let inBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                      frameCapacity: inCapacity),
                      (try? file.read(into: inBuffer, frameCount: inCapacity)) != nil,
                      inBuffer.frameLength > 0 else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if status == .error || conversionError != nil { throw TranscriptionError.bridgeUnavailable }
            if let channel = outBuffer.floatChannelData?[0], outBuffer.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel,
                                                               count: Int(outBuffer.frameLength)))
            }
            reachedEnd = (status == .endOfStream) || outBuffer.frameLength == 0
        }
        guard !samples.isEmpty else { throw TranscriptionError.bridgeUnavailable }
        return samples
    }
}
#else
/// Inactive until scripts/build-whisper.sh vendors the xcframework (T3: needs
/// a Mac). The simulator/dev/test path uses MockTranscriber; on device without
/// the framework, capture parks the memo honestly for sync-later (P3).
enum WhisperBridge {
    static func run(model: URL, audio: URL, initialPrompt: String) async throws -> String {
        throw TranscriptionError.bridgeUnavailable
    }
}
#endif

/// Dev/simulator transcriber: replays a provided transcript (used by UI tests).
struct MockTranscriber: TranscriptionService {
    var canned: String
    var full: Bool = true
    func transcribe(audioAt path: String, primedWith names: [String]) async throws -> TranscriptResult {
        TranscriptResult(text: canned, usedFullModel: full)
    }
}

// MARK: - Recording

/// The mic seam. Same shape as TranscriptionService: no network implementation
/// exists or ever will (PRIV-1 — audio never leaves the device).
protocol AudioRecording {
    func begin() throws
    /// True pause — the session continues where it left off (§7.11 portraits).
    func pause()
    func resume()
    /// Stops and returns the audio file ref (a local path).
    func end() throws -> String
}

#if canImport(AVFoundation) && os(iOS)
import AVFoundation

/// AAC mono 16 kHz — small on disk (audio is retained until the full model has
/// heard it, §7.5) and what WhisperBridge decodes from. PERF-3 budget: mic tap
/// → recording ≤ 300ms, so the session is configured lazily but the recorder
/// starts synchronously.
final class DeviceRecorder: AudioRecording {
    private var recorder: AVAudioRecorder?
    private var url: URL?

    func begin() throws {
        // A denied mic is the user's to fix; anything else we report verbatim.
        if AVAudioApplication.shared.recordPermission == .denied { throw RecordingError.denied }

        try configureSession()

        let dir = try FileManager.default.url(for: .applicationSupportDirectory,
                                              in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("capture-\(UUID().uuidString).m4a")
        let r = try AVAudioRecorder(url: file, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
        ])
        r.prepareToRecord()
        // record() returning false (or an undetermined permission the system is
        // still prompting for) must not leave the UI claiming it's listening.
        guard r.record() else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw RecordingError.didNotStart
        }
        recorder = r
        url = file
    }

    /// Category and mode must be a *compatible pair* — an invalid combination
    /// fails with kAudio_ParamError (-50, logged by CoreAudio as 4294967246).
    /// `.measurement` is the speech-recognition mode: it turns off the system
    /// signal processing that would otherwise reshape input before whisper
    /// hears it. Devices/simulators that reject it fall back rather than
    /// leaving the user with a dead mic.
    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        var lastError: Error?
        for mode: AVAudioSession.Mode in [.measurement, .default] {
            do {
                try session.setCategory(.record, mode: mode)
                try session.setActive(true)
                return
            } catch {
                lastError = error
            }
        }
        do {                                  // last resort: bare record category
            try session.setCategory(.record)
            try session.setActive(true)
        } catch {
            throw RecordingError.sessionFailed(
                String(describing: lastError ?? error))
        }
    }

    func pause() { recorder?.pause() }
    func resume() { recorder?.record() }

    func end() throws -> String {
        guard let recorder, let url else { throw TranscriptionError.noModel }
        recorder.stop()
        self.recorder = nil
        // hand the audio route back — otherwise other apps stay ducked after a memo
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url.path
    }
}
#endif

/// Simulator/UI-test recorder: no mic, a stable fake ref the MockTranscriber ignores.
final class MockRecorder: AudioRecording {
    func begin() throws {}
    func pause() {}
    func resume() {}
    func end() throws -> String { "mock://audio" }
}
