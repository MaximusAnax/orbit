import XCTest
@testable import OrbitApp
import OrbitPipeline

/// Design law graded at the view-model layer — the checks that don't need a
/// rendered frame (EVALS §4.2). The pixel-census half runs in the snapshot job;
/// design_lint.py grades the source-static half on every push.
@MainActor
final class DesignLawTests: XCTestCase {

    // D-8: sections with no content are absent from the tree, not placeholder'd.
    func testD8_emptyGroupsAreAbsent() throws {
        let app = try AppModel(store: .inMemory(), transcription: MockTranscriber(canned: ""))
        let vm = ReviewViewModel(syncRunID: "no-such-run", app: app)
        vm.groups = [.init(id: "p1", name: "Sana", cards: [])]
        XCTAssertTrue(vm.visibleGroups.isEmpty, "an empty person group must not render")
    }

    // D-9: counts shown anywhere equal true counts — no rounding, no "99+".
    func testD9_countsAreTrue() {
        XCTAssertTrue(Copy.setAsideFooter(137).contains("137"))
        XCTAssertFalse(Copy.setAsideFooter(137).contains("+"))
        XCTAssertTrue(Copy.setAsideFooter(1).contains("1"))
    }

    // D-11: forbidden lexicon absent from every user-facing string.
    func testD11_forbiddenLexicon() {
        let forbidden = ["remaining", "overdue", "pending review", "streak"]
        for s in Copy.allStrings {
            for word in forbidden {
                XCTAssertFalse(s.lowercased().contains(word),
                               "forbidden lexicon \(word) in: \(s)")
            }
        }
    }

    // §7.5: the audio-deletion notice is honest about the full-model gate.
    func testAudioNoticeFollowsModelTier() {
        let matcher = NameMatcher(knownNames: [])
        let full = TranscriptReviewViewModel(eventID: "e", text: "t", usedFullModel: true,
                                             matcher: matcher, app: nil)
        let tiny = TranscriptReviewViewModel(eventID: "e", text: "t", usedFullModel: false,
                                             matcher: matcher, app: nil)
        XCTAssertEqual(full.audioNotice, Copy.audioDeletionNotice)
        XCTAssertEqual(tiny.audioNotice, Copy.audioRetainedNotice)
    }

    // PIPE-1 mechanism, UI slice: applying a name fix rewrites the transcript
    // and consumes the suggestion.
    func testNameFixRewritesTranscript() {
        let matcher = NameMatcher(knownNames: ["Nikos"])
        let vm = TranscriptReviewViewModel(eventID: "e", text: "I met Nico's at the picnic",
                                           usedFullModel: true, matcher: matcher, app: nil)
        guard let s = vm.nameSuggestions.first else {
            return XCTFail("expected a name suggestion for Nico's → Nikos")
        }
        vm.applyFix(s)
        XCTAssertTrue(vm.text.contains("Nikos"))
        XCTAssertFalse(vm.text.contains("Nico's"))
        XCTAssertTrue(vm.nameSuggestions.isEmpty)
    }
}
