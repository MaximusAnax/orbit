import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
@testable import OrbitSearch
@testable import OrbitWrite

/// Two ways a search answer can be confidently wrong, both found by review of PR #1.
final class FactAnswerTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        edits = UserEditService(store)
    }

    private func entity(_ id: String, _ name: String, kind: String = "organization") throws {
        try store.db.run(
            "INSERT INTO entity (id, kind, canonical_name) VALUES (?,?,?)",
            [.text(id), .text(kind), .text(name)])
    }

    private func fact(subject: String, predicate: String, value: String?,
                      entity entityID: String?, verbatim: String) throws {
        let event = try edits.captureEvent(.init(
            kind: .encounter, occurredAt: "2026-07-01T10:00:00Z",
            transcript: verbatim, participants: [(subject, .confirmed, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: true)
        try store.db.run(
            """
            INSERT INTO assertion (id, subject_id, predicate, object_entity_id, object_value,
                                   verbatim, date_precision, observed_at, source_event_id, source_kind)
            VALUES (?,?,?,?,?,?,'fuzzy','2026-07-01T10:00:00Z',?,'firsthand')
            """,
            [.text(OrbitID.make()), .text(subject), .text(predicate), .from(entityID),
             .from(value), .text(verbatim), .text(event)])
        try store.rmRebuild()
        try store.rmSearchRebuild()
    }

    /// `object_value` is the literal *beside* the object (DATA-MODEL §2 — "a role
    /// title, a date, a name"), so answering from it alone says "intern" when the
    /// question was "where does she work". Prompt v3 made it sharper still by
    /// putting `origin`/`residence` there for `location`.
    func testWhereSomeoneWorksAnswersTheEmployerNotTheRole() throws {
        let eliah = try edits.createPerson(displayName: "Eliah")
        try entity("e_google", "Google")
        try fact(subject: eliah, predicate: "employment", value: "intern",
                 entity: "e_google", verbatim: "she interned at Google")

        let answer = try Searcher(reader: store.reader).search("where does Eliah work?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "Google", "the role is not the workplace")
    }

    func testWhereSomeoneLivesAnswersThePlaceNotTheQualifier() throws {
        let james = try edits.createPerson(displayName: "James")
        try entity("e_sf", "San Francisco", kind: "place")
        // prompt v3 shape: the qualifier in object_value, the place as the entity
        try fact(subject: james, predicate: "location", value: "residence",
                 entity: "e_sf", verbatim: "he's been in San Francisco ever since")

        let answer = try Searcher(reader: store.reader).search("where does James live?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "San Francisco",
                       "'residence' is the qualifier, not an answer to where")
    }

    /// Facts that never linked an entity still answer from the literal.
    func testALiteralOnlyFactStillAnswers() throws {
        let nikos = try edits.createPerson(displayName: "Nikos")
        try fact(subject: nikos, predicate: "location", value: "Greece",
                 entity: nil, verbatim: "he's from Greece")

        let answer = try Searcher(reader: store.reader).search("where is Nikos from?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "Greece")
    }

    /// The other half of the same predicate: "what is her job" wants the role,
    /// and preferring the entity unconditionally answered it with the company.
    /// Found by review of the first fix — one predicate, two questions.
    func testWhatSomeonesJobIsAnswersTheRoleNotTheEmployer() throws {
        let eliah = try edits.createPerson(displayName: "Eliah")
        try entity("e_google", "Google")
        try fact(subject: eliah, predicate: "employment", value: "intern",
                 entity: "e_google", verbatim: "she interned at Google")

        let answer = try Searcher(reader: store.reader).search("what is Eliah's job?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "intern", "the employer is not the job")
    }

    /// A qualifier is never an answer, whatever was asked — "what" must not
    /// reach past the entity and return "residence".
    func testAQualifierIsNeverAnAnswerEvenForAWhatQuestion() throws {
        let james = try edits.createPerson(displayName: "James")
        try entity("e_sf", "San Francisco", kind: "place")
        try fact(subject: james, predicate: "location", value: "residence",
                 entity: "e_sf", verbatim: "he's been in San Francisco ever since")

        let answer = try Searcher(reader: store.reader).search("what city is James based in?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "San Francisco")
    }

    /// After a merge both rows can carry a first-met anchor. Reading "any row
    /// whose canonical id matches" without an aggregate returns whichever one
    /// SQLite hands back first, so the line could flip between runs.
    func testFirstMetIsTheEarliestAcrossAMergeAndIsStable() throws {
        let winner = try edits.createPerson(displayName: "Sarah")
        let loser = try edits.createPerson(displayName: "Sara")
        func meeting(_ person: String, _ when: String) throws -> String {
            let e = try edits.captureEvent(.init(
                kind: .encounter, occurredAt: when, transcript: "met",
                participants: [(person, .confirmed, nil)]))
            try edits.confirmEvent(e, fullModelTranscribed: true)
            return e
        }
        try edits.setFirstMet(person: winner, event: try meeting(winner, "2025-09-01T10:00:00Z"))
        try edits.setFirstMet(person: loser, event: try meeting(loser, "2023-03-01T10:00:00Z"))
        try edits.mergePerson(loser: loser, winner: winner)
        try store.rmRebuild()

        let answers = try (0..<5).map { _ in
            try store.reader.firstMetDate(person: winner) ?? ""
        }
        XCTAssertEqual(Set(answers).count, 1, "first-met flipped between reads: \(answers)")
        XCTAssertTrue(answers[0].hasPrefix("2023-03"),
                      "the earliest meeting is when you met them; got \(answers[0])")
    }

    /// Decision 6 is a pointer merge: the loser's rows are never rewritten, so
    /// every read has to follow the pointer. Recall does this in eight queries;
    /// search's provenance line did not, so the Desk and the search result
    /// disagreed about the same person after a merge.
    func testLastSeenFollowsAMergePointer() throws {
        let winner = try edits.createPerson(displayName: "Sarah")
        let loser = try edits.createPerson(displayName: "Sara")
        let event = try edits.captureEvent(.init(
            kind: .coffee, occurredAt: "2026-06-15T10:00:00Z",
            transcript: "coffee with Sara", participants: [(loser, .confirmed, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: true)
        try edits.mergePerson(loser: loser, winner: winner)
        try store.rmRebuild()
        try store.rmSearchRebuild()

        let anchor = try Searcher(reader: store.reader).provenanceAnchor(winner)
        XCTAssertTrue(anchor.contains("last seen 2026-06"),
                      "the merged-away id held the only event; anchor was \(anchor.debugDescription)")
    }

    // MARK: the employer asked for by other names (Bugbot, 2026-08-07)

    /// "where" was the only cue that selected the entity, so every other way of
    /// asking for the employer fell to the literal and answered `intern`.
    /// The employer is not the job in either direction.
    func testCompanyPhrasingsAnswerTheEmployerNotTheRole() throws {
        let eliah = try edits.createPerson(displayName: "Eliah")
        try entity("e_google", "Google")
        try fact(subject: eliah, predicate: "employment", value: "intern",
                 entity: "e_google", verbatim: "she interned at Google")

        for query in ["what company does Eliah work for?",
                      "which company does Eliah work for?",
                      "who does Eliah work for?"] {
            let answer = try Searcher(reader: store.reader).search(query)
            guard case .answer(let a) = answer else {
                return XCTFail("expected an answer band for \(query), got \(answer)")
            }
            XCTAssertEqual(a.factAnswer, "Google",
                           "\(query) asks for the employer, not the role")
        }
    }

    /// The other direction has to keep working: a role question must not start
    /// answering with the company just because the cue list grew.
    func testRolePhrasingsStillAnswerTheRole() throws {
        let eliah = try edits.createPerson(displayName: "Eliah")
        try entity("e_google", "Google")
        try fact(subject: eliah, predicate: "employment", value: "intern",
                 entity: "e_google", verbatim: "she interned at Google")

        for query in ["what is Eliah's job?", "what is Eliah's role?", "what is Eliah's title?"] {
            let answer = try Searcher(reader: store.reader).search(query)
            guard case .answer(let a) = answer else {
                return XCTFail("expected an answer band for \(query), got \(answer)")
            }
            XCTAssertEqual(a.factAnswer, "intern", "\(query) asks for the role")
        }
    }

    /// The same gap on the other predicate, found by sweeping the sibling cues
    /// rather than waiting for it to be reported. `entitySeekingCues` learned
    /// "what university" and "which college" while `predicateKeywords` never
    /// did, so those questions could not reach a fact lookup at all — the cue
    /// that would have chosen the school never ran.
    func testSchoolPhrasingsReachTheFactLookup() throws {
        let eliah = try edits.createPerson(displayName: "Eliah")
        try entity("e_cmu", "Carnegie Mellon")
        try fact(subject: eliah, predicate: "education", value: "undergrad",
                 entity: "e_cmu", verbatim: "she did her undergrad at CMU")

        for query in ["what university did Eliah go to?",
                      "which college did Eliah go to?",
                      "what school did Eliah go to?"] {
            let answer = try Searcher(reader: store.reader).search(query)
            guard case .answer(let a) = answer else {
                return XCTFail("expected an answer band for \(query), got \(answer)")
            }
            XCTAssertEqual(a.factAnswer, "Carnegie Mellon",
                           "\(query) asks for the school; 'undergrad' is a qualifier")
        }
    }

    /// Cues are words, not runs of letters. Under substring matching "position"
    /// hides in "disposition", "title" in "entitled", "company" in "accompany"
    /// and "org" in the name Morgan — so a plain question about a person routed
    /// itself into an employment lookup and answered with a fact nobody asked
    /// about. Every case here is a *non*-answer: the query must fall through to
    /// the generic search, which is what "no fact answer" looks like.
    func testALetterRunInsideAWordIsNotACue() throws {
        let morgan = try edits.createPerson(displayName: "Morgan")
        try entity("e_google", "Google")
        try fact(subject: morgan, predicate: "employment", value: "intern",
                 entity: "e_google", verbatim: "she interned at Google")

        for query in ["what is Morgan's disposition?",
                      "what is Morgan entitled to?",
                      "who did Morgan accompany?"] {
            let answer = try Searcher(reader: store.reader).search(query)
            if case .answer(let a) = answer, a.factAnswer != nil {
                XCTFail("\(query) is not an employment question; answered \(a.factAnswer!)")
            }
        }

        // The control: the same person, asked properly, still answers.
        let asked = try Searcher(reader: store.reader).search("where does Morgan work?")
        guard case .answer(let a) = asked else {
            return XCTFail("expected an answer band, got \(asked)")
        }
        XCTAssertEqual(a.factAnswer, "Google")
    }

    /// Keyword tokens are dropped before person matching because the matcher is
    /// fuzzy — but some of that vocabulary is also a name. Job is a name; so is
    /// a contact called City or Org. Dropping their tokens outright meant the
    /// one person whose name is a keyword could never be asked about, and every
    /// token in "where does Job work?" is a keyword.
    func testAPersonWhoseNameIsAKeywordIsStillFound() throws {
        let job = try edits.createPerson(displayName: "Job")
        try entity("e_google", "Google")
        try fact(subject: job, predicate: "employment", value: "intern",
                 entity: "e_google", verbatim: "he interned at Google")

        let answer = try Searcher(reader: store.reader).search("where does Job work?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "Google",
                       "every token here is a predicate keyword, including the name")
    }

    /// The precedence the fallback must not disturb: when a real name is
    /// present, it wins outright. "city" is within edit distance 2 of "Cindy",
    /// so trying vocabulary as a name first would answer about the wrong
    /// person — which is why the strict pass runs first and the fallback only
    /// runs when it found nobody.
    func testVocabularyNeverOutranksARealName() throws {
        let cindy = try edits.createPerson(displayName: "Cindy")
        try entity("e_sf", "San Francisco", kind: "place")
        try fact(subject: cindy, predicate: "location", value: "residence",
                 entity: "e_sf", verbatim: "she's been in San Francisco ever since")

        let answer = try Searcher(reader: store.reader).search("what city is Cindy based in?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "San Francisco")
        XCTAssertEqual(a.firsthand.first?.name, "Cindy")
    }
}
