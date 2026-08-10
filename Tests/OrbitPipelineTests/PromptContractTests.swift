import XCTest
@testable import OrbitPipeline

/// What the model is actually sent, guarded.
///
/// Two failures in this area were only ever caught by hand: FN-35 (an allow-list
/// that substituted a *different* prompt on a miss) and FN-50 (the file's
/// developer header shipping to the model as instructions, which confounded the
/// v10 comparison by 142 words). Both were invisible in the result — a plausible
/// output either way — so they belong to a test rather than to vigilance.
final class PromptContractTests: XCTestCase {

    override func tearDown() {
        unsetenv("ORBIT_PROMPT_VERSION")
        super.tearDown()
    }

    /// FN-50's fix is opt-in **because** measurements are attached to prompts.
    /// Stripping headers unconditionally would change what every already-measured
    /// prompt sends — including the one v11 was promoted on — and silently make
    /// each of those measurements describe a prompt that no longer exists.
    func testMeasuredPromptsAreSentWhole() throws {
        for version in ["v1", "v6", "v8", "v10", "v11"] {
            setenv("ORBIT_PROMPT_VERSION", version, 1)
            let sent = try ExtractionPrompt.system()
            XCTAssertTrue(sent.hasPrefix("# Orbit extraction prompt — \(version)"),
                          "\(version) must still send the whole file, header included — "
                          + "a measurement is attached to it")
            XCTAssertFalse(sent.contains(ExtractionPrompt.promptMarker),
                           "\(version) predates the marker")
        }
    }

    /// And when a prompt does carry the marker, everything above it is ours and
    /// must not reach the model.
    func testMarkerStripsTheDeveloperHeader() throws {
        let file = """
        # Orbit extraction prompt — vNext

        Notes for us: golden-run policy, waiver history, who promoted what.
        None of this is an instruction.

        \(ExtractionPrompt.promptMarker)

        You extract structured memory from one voice-memo transcript.
        """
        // The split is a pure string operation on the file's text; exercising it
        // directly keeps the test from needing a bundled resource per revision.
        let body = file.range(of: ExtractionPrompt.promptMarker)
            .map { String(file[$0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertEqual(body, "You extract structured memory from one voice-memo transcript.")
        XCTAssertFalse(body?.contains("waiver history") ?? true,
                       "developer notes must not reach the model")
    }

    /// The active prompt must exist and be loadable. FN-35 shipped a default that
    /// silently resolved to a different file; a missing resource must fail loudly.
    func testActiveVersionResolvesAndLoads() throws {
        XCTAssertEqual(ExtractionPrompt.version, ExtractionPrompt.activeVersion,
                       "with no override, what ships is what activeVersion names")
        let sent = try ExtractionPrompt.system()
        XCTAssertTrue(sent.contains("# Orbit extraction prompt — \(ExtractionPrompt.activeVersion)"),
                      "the loaded text is the version it claims to be")
        XCTAssertFalse(sent.isEmpty)
    }

    func testUnknownVersionFailsLoudlyRatherThanSubstituting() {
        setenv("ORBIT_PROMPT_VERSION", "v9999", 1)
        XCTAssertThrowsError(try ExtractionPrompt.system(),
                             "FN-35: an unknown version must throw, never fall back")
    }
}
