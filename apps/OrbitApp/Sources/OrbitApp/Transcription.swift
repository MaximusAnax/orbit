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
    enum Tier: String { case floor = "ggml-base.q5_1", ceiling = "ggml-large-v3-turbo-q5_0" }

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
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio)
        try session.setActive(true)
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
        r.record()
        recorder = r
        url = file
    }

    func end() throws -> String {
        guard let recorder, let url else { throw TranscriptionError.noModel }
        recorder.stop()
        self.recorder = nil
        return url.path
    }
}
#endif

/// Simulator/UI-test recorder: no mic, a stable fake ref the MockTranscriber ignores.
final class MockRecorder: AudioRecording {
    func begin() throws {}
    func end() throws -> String { "mock://audio" }
}
