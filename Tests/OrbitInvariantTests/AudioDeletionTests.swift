import XCTest
import Foundation
import OrbitCore
import OrbitSQLite
import OrbitStore
@testable import OrbitWrite

/// PRIV-3: audio deletion is verified at the FILESYSTEM level, honoring the
/// §7.5 full-model gate — a NULLed column with a lingering m4a is not deletion.
final class AudioDeletionTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!
    var tempDir: URL!

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        edits = UserEditService(store)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeRecording(_ name: String) throws -> String {
        let url = tempDir.appendingPathComponent(name)
        try Data("not-really-audio".utf8).write(to: url)
        return url.path
    }

    func capture(audioRef: String) throws -> String {
        let p = try edits.createPerson(displayName: "Sana")
        return try edits.captureEvent(.init(
            kind: .encounter, occurredAt: "2026-07-01T20:00:00Z",
            transcript: "we talked", audioRef: audioRef,
            participants: [(p, .confirmed, nil)]))
    }

    func testFullModelConfirmDeletesTheFile() throws {
        let path = try makeRecording("a.m4a")
        let event = try capture(audioRef: path)
        try edits.confirmEvent(event, fullModelTranscribed: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path),
                       "the recording is gone from disk, not just from the column")
        XCTAssertNil(try store.db.scalar(
            "SELECT raw_audio_ref FROM event WHERE id=?", [.text(event)]).stringValue)
    }

    func testTinyModelConfirmKeepsTheFileUntilUpgrade() throws {
        let path = try makeRecording("b.m4a")
        let event = try capture(audioRef: path)
        try edits.confirmEvent(event, fullModelTranscribed: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                      "tiny-model transcript must NOT trigger deletion (§7.5)")
        // the upgrade pass closes the gate
        try edits.deleteAudioAfterUpgrade(event: event)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testDiscardDeletesTheFile() throws {
        let path = try makeRecording("c.m4a")
        let event = try capture(audioRef: path)
        try edits.discardEvent(event)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path),
                       "a discarded capture leaves no recording behind")
    }
}
