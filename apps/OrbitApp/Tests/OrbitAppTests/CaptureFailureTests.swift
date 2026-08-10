import XCTest
@testable import OrbitApp
import OrbitCore

/// A capture that can't be transcribed must never become a dead end: the memo
/// parks, the home footer offers it back, and the tap that fails **says why**.
/// (P3 — capture never hard-fails; the silent-tap bug this pins was real.)
@MainActor
final class CaptureFailureTests: XCTestCase {

    struct FailingTranscriber: TranscriptionService {
        var error: Error = TranscriptionError.bridgeUnavailable
        func transcribe(audioAt path: String, primedWith names: [String]) async throws -> TranscriptResult {
            throw error
        }
    }

    func makeApp(_ error: Error = TranscriptionError.bridgeUnavailable) throws -> AppModel {
        let app = try AppModel(store: .inMemory(),
                               transcription: FailingTranscriber(error: error))
        app.ensureSelf(named: "Abdoul")
        return app
    }

    func testFailedTranscriptionParksTheMemoAndExplainsItself() async throws {
        let app = try makeApp()
        await app.finishRecording(audioRef: "/tmp/nonexistent.m4a", participants: [], kind: .encounter)

        // the recording is kept as a captured event — nothing is lost (P3)
        let captured = try app.store.db.scalar(
            "SELECT COUNT(*) FROM event WHERE lifecycle='captured' AND transcript IS NULL").intValue
        XCTAssertEqual(captured, 1)
        // it shows up as resumable...
        XCTAssertEqual(app.waitingMemos.count, 1)
        XCTAssertEqual(app.waitingMemos.first?.stage, .needsTranscription)
        // ...and the failure is stated, not swallowed
        XCTAssertEqual(app.captureNotice, Copy.transcriptionUnavailable)
    }

    func testResumingAStillUntranscribableMemoStillExplainsItself() async throws {
        let app = try makeApp()
        await app.finishRecording(audioRef: "/tmp/nonexistent.m4a", participants: [], kind: .encounter)
        app.captureNotice = nil
        let memo = try XCTUnwrap(app.waitingMemos.first)

        app.resume(memo)                       // the home-footer tap
        // the retry is async; drain it
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(app.captureNotice, "a tap that fails must not do nothing")
        XCTAssertNil(app.pendingCapture, "and it must not strand the UI mid-flow")
    }

    func testDeniedSpeechPermissionSaysWhereToFixIt() async throws {
        let app = try makeApp(TranscriptionError.speechDenied)
        await app.finishRecording(audioRef: "/tmp/nonexistent.m4a", participants: [], kind: .encounter)
        XCTAssertEqual(app.captureNotice, Copy.speechDenied)
    }

    /// PRIV-1: refusing off-device recognition is a distinct, stated outcome —
    /// never a silent downgrade to sending the audio away.
    func testOffDeviceRefusalIsItsOwnNotice() async throws {
        let app = try makeApp(TranscriptionError.onDeviceUnavailable)
        await app.finishRecording(audioRef: "/tmp/nonexistent.m4a", participants: [], kind: .encounter)
        XCTAssertEqual(app.captureNotice, Copy.transcriptionOffDeviceRefused)
    }

    /// The cascade returns the first success and only fails when every stage does.
    func testCascadeFallsThroughToTheWorkingStage() async throws {
        let cascade = CascadingTranscriber([
            FailingTranscriber(),
            MockTranscriber(canned: "the floor model heard this", full: false),
        ])
        let result = try await cascade.transcribe(audioAt: "/tmp/x.m4a", primedWith: [])
        XCTAssertEqual(result.text, "the floor model heard this")
        XCTAssertFalse(result.usedFullModel, "a floor transcript never unlocks audio deletion (§7.5)")
    }
}
