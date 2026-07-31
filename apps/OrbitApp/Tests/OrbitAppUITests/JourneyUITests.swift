import XCTest

/// The tap-level halves of the J-suite (EVALS §4.1): friction budgets and
/// rendered-absence assertions. DB end-states for the same journeys are
/// asserted in OrbitAppTests/JourneyModelTests through the identical code path.
/// Friction budgets are ◊ provisional — measured here, ratified by Abdoul.
/// (XCUIAutomation is MainActor-isolated under Swift 6.)
@MainActor
final class JourneyUITests: XCTestCase {

    static let nikosTranscript =
        "I met Nikos at the picnic. Nikos is from Greece. He was there for startup school. " +
        "He was a very down-to-earth guy, super nice to talk to, very kind"

    // Same shape as docs/evals/fixtures/nikos.json (person + entity + 3 assertions).
    static let nikosPayload = #"""
    {"people":[{"ref":"p_nikos","name_as_heard":"Nikos","match":"new","existing_person_id":null,"match_rationale":null,"status":"active"}],"entities":[{"ref":"e_ycss","name_as_heard":"Y Combinator Startup School","kind":"event_series","existing_entity_id":null,"part_of_ref":null,"aliases":["startup school"]}],"assertions":[{"subject_ref":"p_nikos","predicate":"location","object_entity_ref":null,"object_person_ref":null,"object_value":"Greece","verbatim":"Nikos is from Greece","valid_from":null,"valid_to":null,"date_precision":"fuzzy","source_kind":"firsthand","attributed_to_ref":null,"hedged":false,"confidence":null,"thread_ref":null},{"subject_ref":"p_nikos","predicate":"life_event","object_entity_ref":"e_ycss","object_person_ref":null,"object_value":"attended Y Combinator Startup School","verbatim":"He was there for startup school","valid_from":"2026-07","valid_to":null,"date_precision":"month","source_kind":"firsthand","attributed_to_ref":null,"hedged":false,"confidence":null,"thread_ref":null},{"subject_ref":"p_nikos","predicate":"trait","object_entity_ref":null,"object_person_ref":null,"object_value":"down-to-earth, kind","verbatim":"He was a very down-to-earth guy, super nice to talk to, very kind","valid_from":null,"valid_to":null,"date_precision":"fuzzy","source_kind":"firsthand","attributed_to_ref":null,"hedged":false,"confidence":null,"thread_ref":null}],"episodes":[],"threads":[],"thread_closures":[],"loops":[],"contact_points":[],"state_declarations":[],"corrections":[],"ambiguities":[]}
    """#

    var taps = 0

    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "ORBIT_UITEST": "1",
            "ORBIT_UITEST_TRANSCRIPT": Self.nikosTranscript,
            "ORBIT_UITEST_PAYLOAD": Self.nikosPayload,
        ]
        app.launch()
        taps = 0
        return app
    }

    func tap(_ element: XCUIElement, timeout: TimeInterval = 8) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "expected element for tap: \(element)")
        element.tap()
        taps += 1
    }

    /// Drive capture → transcript confirm → proposal review. Returns at the
    /// review screen with the tap count so far.
    func reachReview(_ app: XCUIApplication) {
        tap(app.buttons["home.mic"])
        tap(app.buttons["capture.mic"])                       // start recording
        tap(app.buttons["capture.mic"])                       // stop → transcribe
        XCTAssertTrue(app.staticTexts["Here's what I heard"].waitForExistence(timeout: 8))
        tap(app.buttons["Looks right — save this"])
        XCTAssertTrue(app.staticTexts["Does this look right?"].waitForExistence(timeout: 8))
    }

    // J-1: capture → transcript → review → sync, single person. Budget ◊ ≤ 12 taps.
    func testJ1_singlePersonCapture() {
        let app = launch()
        reachReview(app)
        // settle every card (per-person accept-all when offered, else Yes)
        while app.buttons["Yes"].firstMatch.waitForExistence(timeout: 2) {
            tap(app.buttons["Yes"].firstMatch)
        }
        tap(app.buttons["Done for now"])
        XCTAssertLessThanOrEqual(taps, 12, "J-1 friction budget ◊")
    }

    // J-3: defer everything in ≤ 3 taps from review; zero badges/nags after.
    func testJ3_deferEverythingNoNags() {
        let app = launch()
        reachReview(app)
        let before = taps
        tap(app.buttons["Later"].firstMatch)     // one tap defers the whole event
        XCTAssertLessThanOrEqual(taps - before, 3, "J-3 friction budget ◊")

        // back home: the ONLY ambient trace is the plain footer line — a true
        // count in words, no badge anywhere in the hierarchy (D-2/D-9)
        // the footer is a quiet tappable line (a Button wrapping plain text)
        XCTAssertTrue(app.buttons["home.setAsideFooter"].waitForExistence(timeout: 8))
        let footer = app.buttons["home.setAsideFooter"].label
        XCTAssertTrue(footer.contains("set aside"), "footer speaks plainly: \(footer)")
        XCTAssertFalse(footer.contains("+"), "counts are true counts")
    }

    // J-5: typed micro-note — text is the transcript; straight to review.
    func testJ5_typedNote() {
        let app = launch()
        tap(app.buttons["home.mic"])
        let field = app.textFields["capture.typedNote"]
        tap(field)
        field.typeText("Sana got the Berlin offer\n")
        XCTAssertTrue(app.staticTexts["Does this look right?"].waitForExistence(timeout: 8))
    }
}
