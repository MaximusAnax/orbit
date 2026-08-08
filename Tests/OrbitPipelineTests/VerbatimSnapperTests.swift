import XCTest
@testable import OrbitPipeline

/// FN-38 — PIPE-6 by construction.
///
/// The cases below are not invented: each is a real quote from the k=10
/// collection of 2026-08-08, paired with the real Eliah transcript, chosen
/// because the extractor actually produced it.
final class VerbatimSnapperTests: XCTestCase {

    static var transcript: String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir = dir.deletingLastPathComponent() }
        return (try? String(contentsOf: dir.appendingPathComponent("mock_memos/transcripts/Eliah.txt"),
                            encoding: .utf8)) ?? ""
    }

    func testExactQuotePassesThroughUnchanged() {
        let src = Self.transcript
        XCTAssertFalse(src.isEmpty)
        let quote = "we both interned in the Pacific Northwest that summer"
        XCTAssertEqual(VerbatimSnapper.locate(quote, in: src), quote)
    }

    /// The model returned this with a newline where the source has a space.
    /// Byte-inexact, word-identical — PIPE-6 called it a fabricated quote.
    func testWhitespaceDifferenceSnapsToTheSourceSlice() {
        let src = Self.transcript
        let quote = "we love \n um like video games"
        let got = VerbatimSnapper.locate(quote, in: src)
        XCTAssertNotNil(got)
        XCTAssertTrue(src.contains(got ?? "|nope|"),
                      "a snapped quote must be a real slice of the transcript")
        XCTAssertTrue((got ?? "").contains("video games"))
    }

    /// A real near-miss: the model wrote "but yeah, so" where the source reads
    /// "um and yeah so", keeping the "we we we" stutter intact. Scores 0.812 on
    /// word-LCS with punctuation attached and 0.938 without — this test is the
    /// regression guard for that decision.
    func testAlteredConnectorStillLocatesAndReturnsTheSourceText() {
        let src = Self.transcript
        let quote = "but yeah, so we we we went to japan and then That was a great time"
        let got = VerbatimSnapper.locate(quote, in: src)
        XCTAssertNotNil(got, "a 0.94-similarity near-miss must locate")
        XCTAssertTrue(src.contains(got ?? "|nope|"))
        // The stored record is the transcript's wording, not the model's.
        XCTAssertFalse((got ?? "").hasPrefix("but yeah, so"))
    }

    func testFabricatedQuoteIsRejected() {
        let src = Self.transcript
        let invented = "he told me he was quitting his job to open a bakery in Lisbon next spring"
        XCTAssertNil(VerbatimSnapper.locate(invented, in: src),
                     "a quote with no anchor must not be silently accepted")
    }

    func testEmptyAndOverlongQuotesAreRejectedNotCrashed() {
        let src = Self.transcript
        XCTAssertNil(VerbatimSnapper.locate("", in: src))
        XCTAssertNil(VerbatimSnapper.locate("   \n  ", in: src))
    }

    /// The whole point: a claim whose quote cannot be found is dropped before it
    /// can reach a review card as something the owner said.
    func testSnapDropsUnanchoredClaimsAndCountsWhatItDid() {
        let src = "I saw Nikos at the picnic and he seemed genuinely happy about it."
        let json = """
        {"people":[],"entities":[],"assertions":[
          {"subject_ref":"self","predicate":"trait","object_value":"happy",
           "verbatim":"he seemed genuinely happy","date_precision":"none",
           "source_kind":"firsthand","hedged":false},
          {"subject_ref":"self","predicate":"goal","object_value":"marathon",
           "verbatim":"he is training for a marathon in Berlin","date_precision":"none",
           "source_kind":"firsthand","hedged":false}],
         "episodes":[],"threads":[],"thread_closures":[],"loops":[],
         "contact_points":[],"state_declarations":[],"corrections":[],"ambiguities":[]}
        """
        guard let payload = try? JSONDecoder().decode(ExtractionPayload.self,
                                                      from: Data(json.utf8)) else {
            return XCTFail("fixture did not decode — schema drift?")
        }
        XCTAssertEqual(payload.assertions.count, 2)
        let (snapped, report) = VerbatimSnapper.snap(payload, to: src)
        XCTAssertEqual(snapped.assertions.count, 1, "the invented claim should be gone")
        XCTAssertEqual(report.rejected, 1)
        XCTAssertEqual(report.exact + report.snapped, 1)
        for a in snapped.assertions {
            XCTAssertTrue(src.contains(a.verbatim),
                          "every surviving verbatim is a real slice of the source")
        }
    }
}
