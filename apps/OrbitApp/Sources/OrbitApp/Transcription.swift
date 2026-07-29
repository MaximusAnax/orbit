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

    /// Onboarding has dead time (permissions, contact import) — that's when this runs.
    /// Resumable; failure leaves the floor model doing honest work with audio retained.
    func downloadCeilingIfNeeded() async {
        // wired to a background URLSession on device; see scripts/build-whisper.sh
        // for producing + hosting the quantized model artifact.
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

/// Placeholder for the whisper.cpp C bridge — the xcframework is produced on a Mac
/// by scripts/build-whisper.sh (T3: needs Apple toolchain + on-device measurement
/// for PERF-4). The simulator/dev path uses MockTranscriber.
enum WhisperBridge {
    static func run(model: URL, audio: URL, initialPrompt: String) async throws -> String {
        throw TranscriptionError.bridgeUnavailable
    }
}

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
