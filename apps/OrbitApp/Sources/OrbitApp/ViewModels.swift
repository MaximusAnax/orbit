import Foundation
import OrbitCore
import OrbitSQLite
import OrbitStore
import OrbitWrite
import OrbitPipeline

// View models hold every decision the D-suite grades, so the laws are testable
// without rendering: D-8 (empty sections are ABSENT, never placeholder'd),
// D-9 (counts are true counts), D-2 (no counter is ever exposed as a badge).

/// Transcript review — the review that makes audio deletion consequential (§7.5).
@MainActor
final class TranscriptReviewViewModel: ObservableObject, Identifiable {
    let eventID: String
    @Published var text: String
    let usedFullModel: Bool
    @Published var nameSuggestions: [NameMatcher.Suggestion]
    let inconsistentNameForms: [[String]]     // PIPE-1b surface
    weak var app: AppModel?

    init(eventID: String, text: String, usedFullModel: Bool, matcher: NameMatcher, app: AppModel?) {
        self.eventID = eventID
        self.text = text
        self.usedFullModel = usedFullModel
        self.nameSuggestions = matcher.suggestions(in: text)
        self.inconsistentNameForms = matcher.inconsistentForms(in: text)
        self.app = app
    }

    /// The §7.5 notice is honest about the gate: deletion only follows the full model.
    var audioNotice: String {
        usedFullModel ? Copy.audioDeletionNotice : Copy.audioRetainedNotice
    }

    func applyFix(_ suggestion: NameMatcher.Suggestion) {
        // Replace THE occurrence the suggestion points at, not every substring
        // ("Ann" must never rewrite "Anniversary"). Ranges drift as earlier
        // fixes land, so verify the token is still there before using it;
        // otherwise fall back to the first whole-word occurrence.
        let chars = Array(text)
        let range = suggestion.range
        if range.lowerBound >= 0, range.upperBound <= chars.count,
           String(chars[range.lowerBound..<range.upperBound])
               .trimmingCharacters(in: .punctuationCharacters) == suggestion.heard {
            let head = String(chars[..<range.lowerBound])
            let tokenText = String(chars[range.lowerBound..<range.upperBound])
            let tail = String(chars[range.upperBound...])
            let fixedToken = tokenText.replacingOccurrences(of: suggestion.heard,
                                                            with: suggestion.candidate)
            text = head + fixedToken + tail
        } else if let wordRange = text.range(
            of: "\\b\(NSRegularExpression.escapedPattern(for: suggestion.heard))\\b",
            options: .regularExpression) {
            text = text.replacingCharacters(in: wordRange, with: suggestion.candidate)
        }
        nameSuggestions.removeAll { $0 == suggestion }
    }

    func confirm() {
        app?.transcriptConfirmed(eventID: eventID, finalText: text, usedFullModel: usedFullModel)
    }

    /// Step away mid-review. This has to save the edits — every correction he
    /// made, including the name fixes he accepted, lives only in `text` until
    /// it's written, and the next pick-up reloads from the ledger. It also has
    /// to refresh the footer, or the memo reads as having vanished when it is
    /// sitting right there waiting (J-11).
    func later() {
        guard let app else { return }
        try? app.edits.editTranscript(event: eventID, transcript: text)
        app.pendingCapture = nil
        app.refreshAmbient()
    }

    func discard() {
        _ = try? app.map { try $0.edits.discardEvent(eventID) }
        app?.pendingCapture = nil
        app?.refreshAmbient()      // the footer counts this memo until it's told
    }
}

/// Proposal review — person-grouped cards (ratified structure, DESIGN §12):
/// quotes light the transcript, settled lines stay visible, "Later" is frictionless.
@MainActor
final class ReviewViewModel: ObservableObject, Identifiable {
    struct Card: Identifiable {
        let id: String
        let op: ProposalOp
        var quote: String            // memory voice, ember-wash left rule
        let rationale: String        // sans — the system explaining itself (P9)
        let hearsayTeller: String?   // hearsay chip when secondhand (§9)
        var mappedFact: String?      // the structured fact this card would save
        let question: String?        // DISAMBIGUATE ask-cards
        let candidates: [(id: String, name: String)]
        let stateSuggestion: String? // PROPOSE_STATE: mapped orbit/intent, shown AS a suggestion
        let isEpisode: Bool          // CREATE_EVENT reconstructed episode (§7.11)
        let payload: String          // raw payload JSON — the Edit sheet prefll
        var settled: String?         // "Saved" / "Skipped" / "Set aside"
        /// Why this card hasn't settled yet, when a tap didn't take.
        var blocked: String?

        /// The ASSERT rationale is the verbatim in curly quotes, which the card
        /// already renders above it — printing both put the same sentence on
        /// screen twice and made every fact look like an unprocessed transcript
        /// span. Compared on content, not on the quoting, so a hedge note or any
        /// rationale that adds something still shows.
        var rationaleEchoesQuote: Bool {
            let stripped = rationale
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{201C}\u{201D}\" "))
            return stripped == quote.trimmingCharacters(in: .whitespaces)
        }
    }

    struct PersonGroup: Identifiable {
        let id: String               // person id or ref
        let name: String
        var cards: [Card]
    }

    @Published var groups: [PersonGroup]
    /// Corrections he made in this review, keyed by ref. Display-only until the
    /// card carrying the ref is accepted.
    @Published var renames: [String: String] = [:]
    /// Names as the extractor supplied them, before any correction.
    private var baseNames: [String: String] = [:]
    let syncRunID: String
    weak var app: AppModel?
    private let service: ProposalResolutionService

    init(syncRunID: String, app: AppModel) {
        self.syncRunID = syncRunID
        self.app = app
        self.service = app.proposals
        self.groups = Self.load(syncRunID: syncRunID, app: app)
        let rows = (try? app.store.reader.pendingProposals(syncRun: syncRunID)) ?? []
        self.baseNames = Self.refNames(rows: rows, syncRunID: syncRunID, app: app)
    }

    /// Refs (`person_david`, `entity_new_york`) are the extractor's internal
    /// wiring: they join items inside one payload and only become real ids when
    /// he accepts the CREATE_PERSON / LINK card that introduces them. Until
    /// then the name exists only on that sibling proposal — so gather it, or
    /// every card in the run shows plumbing where a name belongs.
    static func refNames(rows: [Row], syncRunID: String, app: AppModel) -> [String: String] {
        var names: [String: String] = [:]
        for row in rows {
            guard let payload = row.text("payload") else { continue }
            let dict = decode(payload)
            guard let ref = dict["ref"] as? String else { continue }
            if let name = dict["display_name"] as? String ?? dict["canonical_name"] as? String {
                names[ref] = name
            }
        }
        // Accepting the CREATE_PERSON / LINK card removes it from the pending
        // set, which used to take the only copy of the name with it — every
        // remaining card in the run then fell back to printing `person_david`.
        // The binding survives in the run-scoped ref tables, so read it back.
        let bindings = """
            SELECT r.ref AS ref, p.display_name AS name
            FROM sync_person_ref r JOIN person p ON p.id = r.person_id
            WHERE r.sync_run_id = ?
            UNION ALL
            SELECT r.ref AS ref, e.canonical_name AS name
            FROM sync_entity_ref r JOIN entity e ON e.id = r.entity_id
            WHERE r.sync_run_id = ?
            """
        for row in (try? app.store.db.query(bindings,
                                            [.text(syncRunID), .text(syncRunID)])) ?? [] {
            if let ref = row.text("ref"), let name = row.text("name") { names[ref] = name }
        }
        return names
    }

    static func load(syncRunID: String, app: AppModel) -> [PersonGroup] {
        guard let rows = try? app.store.reader.pendingProposals(syncRun: syncRunID) else { return [] }
        let names = Self.refNames(rows: rows, syncRunID: syncRunID, app: app)
        var byPerson: [String: PersonGroup] = [:]
        var order: [String] = []
        for row in rows {
            guard let id = row.text("id"), let opRaw = row.text("op"),
                  let op = ProposalOp(rawValue: opRaw),
                  let payload = row.text("payload") else { continue }
            let (personKey, personName) = Self.subjectOf(op: op, payload: payload,
                                                         targetPerson: row.text("target_person_id"),
                                                         refNames: names, app: app)
            let card = Card(
                id: id, op: op,
                quote: Self.quoteOf(op: op, payload: payload),
                rationale: row.text("rationale") ?? "",
                hearsayTeller: Self.tellerOf(payload: payload, app: app),
                mappedFact: Self.mappedFactOf(op: op, payload: payload,
                                              refNames: names, app: app)
                    ?? Self.entityKindOf(op: op, payload: payload,
                                         refNames: names, app: app),
                question: Self.questionOf(op: op, payload: payload),
                candidates: Self.candidatesOf(op: op, payload: payload, app: app),
                stateSuggestion: Self.stateSuggestionOf(op: op, payload: payload),
                isEpisode: op == .createEvent,
                payload: payload,
                settled: nil)
            if byPerson[personKey] == nil {
                byPerson[personKey] = PersonGroup(id: personKey, name: personName, cards: [])
                order.append(personKey)
            }
            byPerson[personKey]?.cards.append(card)
        }
        return order.compactMap { byPerson[$0] }
    }

    // MARK: - Inline renaming
    //
    // Transcription hears "Amaad" for Ahmad, and a voice note says "Colorstack
    // conference" for what is really the StackedUp Summit '26 — the real name is
    // never in the audio, so it can only enter here. Because every card resolves
    // names through the run's refs, correcting one ref corrects every card that
    // mentions it; the fix belongs to the ref, not to the card it was noticed on.
    //
    // The correction rides along to the ledger on acceptance (`acceptEdited`), so
    // nothing is written until he says yes — the review still decides (P5). For
    // entities the heard phrasing survives in the payload's `aliases`, untouched
    // here, which is what makes the next "Colorstack conference" resolve to the
    // renamed entity (§7.10 guarantee 3).

    /// The ref this card introduces, if it introduces one.
    static func introducedRef(op: ProposalOp, payload: String) -> String? {
        guard op == .createPerson || op == .link else { return nil }
        return decode(payload)["ref"] as? String
    }

    /// Renameable only where the rename would actually be written. A LINK card
    /// that matched an existing entity applies through the
    /// `if let existing = p.existingEntityID` branch, which reuses the row and
    /// never touches `canonical_name` — so offering the edit there would change
    /// the screen and silently write nothing. Renaming a **saved** entity needs
    /// a write path that does not exist yet (no UPDATE of `canonical_name`
    /// anywhere in OrbitWrite); until it does, this affordance stays where it
    /// tells the truth.
    func renameableRef(_ card: Card) -> String? {
        guard let ref = Self.introducedRef(op: card.op, payload: card.payload) else { return nil }
        if card.op == .link, Self.decode(card.payload)["existing_entity_id"] != nil { return nil }
        return ref
    }

    func currentName(forRef ref: String) -> String {
        renames[ref] ?? baseNames[ref] ?? ref
    }

    func rename(ref: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentName(forRef: ref) else { return }
        renames[ref] = trimmed
        rebuildDisplay()
    }

    /// Re-derive every card's display text from its stored payload under the new
    /// names. Deliberately not a reload: settled cards are gone from the pending
    /// query, and their grey lines are part of the record of this review.
    private func rebuildDisplay() {
        guard let app else { return }
        var names = baseNames.merging(renames) { _, renamed in renamed }
        // Once a ref is applied it is referenced by id, not by ref — so mirror
        // every correction onto its bound id, or accepting the person card makes
        // the old name reappear on every card that mentions them.
        for (ref, newName) in renames {
            for table in ["sync_person_ref", "sync_entity_ref"] {
                let col = table == "sync_person_ref" ? "person_id" : "entity_id"
                if let id = try? app.store.db.scalar(
                    "SELECT \(col) FROM \(table) WHERE sync_run_id=? AND ref=?",
                    [.text(syncRunID), .text(ref)]).stringValue {
                    names[id] = newName
                }
            }
        }
        groups = groups.map { group in
            var rebuilt = group
            rebuilt.cards = group.cards.map { card in
                var c = card
                c.quote = Self.introducedRef(op: card.op, payload: card.payload)
                    .map { names[$0] ?? card.quote } ?? card.quote
                c.mappedFact = Self.mappedFactOf(op: card.op, payload: card.payload,
                                                 refNames: names, app: app)
                    ?? Self.entityKindOf(op: card.op, payload: card.payload,
                                         refNames: names, app: app)
                return c
            }
            return PersonGroup(id: group.id, name: names[group.id] ?? group.name,
                               cards: rebuilt.cards)
        }
    }

    /// The payload as it should be written, with any correction folded in.
    private func editedPayload(for card: Card) -> String? {
        guard let ref = renameableRef(card), let newName = renames[ref] else { return nil }
        var dict = Self.decode(card.payload)
        dict[card.op == .createPerson ? "display_name" : "canonical_name"] = newName
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Decisions — each writes the J-12 outcome row through the funnel.

    func accept(_ card: Card) {
        // a corrected name is an accept-with-edits, so the ledger gets the name
        // he fixed rather than the one the transcript guessed
        if let edited = editedPayload(for: card) {
            acceptEdited(card, payloadJSON: edited)
            return
        }
        settle(card) { try self.service.resolve(proposal: card.id, .accept) }
    }

    func acceptEdited(_ card: Card, payloadJSON: String) {
        settle(card) { try self.service.resolve(proposal: card.id, .acceptEdited(payloadJSON: payloadJSON)) }
    }

    func reject(_ card: Card, reason: RejectionReason?) {
        settle(card) { try self.service.resolve(proposal: card.id, .reject(reason: reason)) }
    }

    func setAside(_ card: Card) {
        settle(card) { try self.service.resolve(proposal: card.id, .defer_) }
    }

    func choose(_ card: Card, candidate: String) {
        settle(card) { try self.service.resolve(proposal: card.id, .chooseCandidate(personID: candidate)) }
    }

    func keepUnresolved(_ card: Card) {
        settle(card) { try self.service.resolve(proposal: card.id, .acceptUnresolved) }
    }

    /// Accept a reconstructed episode AND mark it as the first meeting —
    /// `first_met_event_id` links to whichever episode the user confirms as
    /// the meeting; no special case in the data model (§7.11).
    func acceptAsFirstMet(_ card: Card) {
        guard card.op == .createEvent, let app else { return }
        accept(card)
        do {
            // the freshly created reconstructed event: derived from this sync
            // run's source event AND matching this card's occurred_at — the
            // fixed clock means confirmed_at can tie, so match the payload
            let occurredAt = ((try? JSONSerialization.jsonObject(
                with: Data(card.payload.utf8))) as? [String: Any])?["occurred_at"] as? String
            guard let source = try app.store.db.scalar(
                "SELECT event_id FROM sync_run WHERE id=?", [.text(syncRunID)]).stringValue,
                  let event = try app.store.db.scalar(
                    """
                    SELECT id FROM event WHERE derived_from_event_id=?
                      AND (? IS NULL OR occurred_at = ?)
                    ORDER BY rowid DESC LIMIT 1
                    """, [.text(source), .from(occurredAt), .from(occurredAt)]).stringValue,
                  let person = try app.store.db.query(
                    """
                    SELECT ep.person_id FROM event_participant ep
                    JOIN person p ON p.id = ep.person_id
                    WHERE ep.event_id=? AND p.is_self=0 LIMIT 1
                    """, [.text(event)]).first?.text("person_id")
            else { return }
            try app.edits.setFirstMet(person: person, event: event)
        } catch {
            // the episode is saved either way; first-met stays settable from the Desk
        }
    }

    /// Per-person accept-all (ratified interactive behavior).
    func acceptAll(in group: PersonGroup) {
        for card in group.cards where card.settled == nil && card.question == nil {
            accept(card)
        }
    }

    /// Cards whose accept hit a dependency that hasn't been accepted yet
    /// (e.g. an assertion referencing an entity whose LINK card lives in
    /// another group). Retried automatically after every successful settle,
    /// so accept-all converges regardless of tap order.
    private var dependencyWaiters: [Card] = []

    private func settle(_ card: Card, _ op: () throws -> Void) {
        do {
            try op()
            let label = (try? labelFor(cardID: card.id)) ?? Copy.saved
            for gi in groups.indices {
                if let ci = groups[gi].cards.firstIndex(where: { $0.id == card.id }) {
                    groups[gi].cards[ci].settled = label
                    groups[gi].cards[ci].blocked = nil
                }
            }
            app?.refreshAmbient()
            retryDependencyWaiters()
        } catch {
            // The card stays unsettled either way — plain ink, never red (D-1).
            // What it must not do is stay unsettled *silently*: a Yes that
            // appears to do nothing reads as a broken button, and the reason is
            // right here in the error.
            if case WriteError.pendingDependency(_) = error {
                dependencyWaiters.append(card)
                mark(card, blocked: Copy.cardWaitingOnDependency)
            } else {
                mark(card, blocked: Copy.cardCouldNotSave)
            }
        }
    }

    private func mark(_ card: Card, blocked: String?) {
        for gi in groups.indices {
            if let ci = groups[gi].cards.firstIndex(where: { $0.id == card.id }) {
                groups[gi].cards[ci].blocked = blocked
            }
        }
    }

    private func retryDependencyWaiters() {
        guard !dependencyWaiters.isEmpty else { return }
        let waiting = dependencyWaiters
        dependencyWaiters = []
        for card in waiting where stillPending(card) {
            accept(card)
        }
    }

    private func stillPending(_ card: Card) -> Bool {
        groups.contains { $0.cards.contains { $0.id == card.id && $0.settled == nil } }
    }

    private func labelFor(cardID: String) throws -> String {
        guard let app else { return Copy.saved }
        let state = try app.store.db.scalar(
            "SELECT state FROM proposal WHERE id=?", [.text(cardID)]).stringValue
        switch state {
        case "accepted": return Copy.saved
        case "rejected": return Copy.skipped
        case "deferred": return Copy.setAside
        default: return Copy.saved
        }
    }

    var allSettled: Bool {
        groups.allSatisfy { $0.cards.allSatisfy { $0.settled != nil } }
    }

    /// D-8: sections with nothing pending are absent from the tree, not placeholder'd.
    var visibleGroups: [PersonGroup] {
        groups.filter { !$0.cards.isEmpty }
    }

    func finish() {
        app?.pendingCapture = nil
        app?.refreshAmbient()
    }

    // payload introspection helpers

    private static func decode(_ payload: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] ?? [:]
    }

    static func subjectOf(op: ProposalOp, payload: String, targetPerson: String?,
                          refNames: [String: String], app: AppModel) -> (String, String) {
        let dict = decode(payload)
        func nameOf(_ id: String) -> String {
            (try? app.store.reader.person(id)?.text("display_name")) ?? "…"
        }
        if let target = targetPerson { return (target, refNames[target] ?? nameOf(target)) }
        for key in ["subject", "person"] {
            if let sub = dict[key] as? [String: Any] {
                if let id = sub["person_id"] as? String { return (id, refNames[id] ?? nameOf(id)) }
                if let ref = sub["person_ref"] as? String {
                    // the name lives on this run's CREATE_PERSON card, not here
                    return (ref, dict["display_name"] as? String ?? refNames[ref] ?? ref)
                }
            }
        }
        // Entity LINK cards used to become one group each, so the group header
        // and the card underneath printed the same name twice, five times over.
        // They are context, not people — one section holds all of them.
        if op == .link { return ("context", Copy.contextGroupTitle) }
        if let ref = dict["ref"] as? String {
            return (ref, dict["display_name"] as? String ?? dict["canonical_name"] as? String ?? ref)
        }
        return ("event", "This event")
    }

    static func quoteOf(op: ProposalOp, payload: String) -> String {
        let dict = decode(payload)
        return (dict["verbatim"] as? String)
            ?? (dict["narrative_quote"] as? String)
            ?? (dict["narrative"] as? String)
            ?? (dict["description"] as? String)
            ?? (dict["display_name"] as? String)
            ?? (dict["canonical_name"] as? String)
            ?? (dict["title"] as? String)
            ?? ""
    }

    /// The structured fact the card is actually asking him to save — the "tag"
    /// half of the prompt's "tag the concept, keep the sentence" rule. Without
    /// it the card showed the transcript span and nothing else, so a long
    /// rambling sentence looked like the fact, and there was no way to tell what
    /// Orbit had actually understood from it.
    static func mappedFactOf(op: ProposalOp, payload: String,
                             refNames: [String: String], app: AppModel) -> String? {
        guard op == .assert || op == .close || op == .correct else { return nil }
        let dict = decode(payload)
        guard let predicate = dict["predicate"] as? String else { return nil }

        // DATA-MODEL §2: `object_entity_id` carries the org/school/place and
        // `object_value` carries the literal beside it — a role title, a degree,
        // a status. They are not alternatives, and choosing one hid the other:
        // "works at OpenAI as a member of technical staff" rendered as
        // "employment · member of technical staff", losing the employer.
        // `refNames` is keyed by ref AND by resolved id, so a correction still
        // wins after the card that introduced the name has been accepted —
        // otherwise the stored row answers first and the review shows two
        // different names for one person.
        var entityName: String?
        if let entity = dict["object_entity"] as? [String: Any] {
            if let id = entity["entity_id"] as? String {
                entityName = refNames[id] ?? (try? app.store.db.scalar(
                    "SELECT canonical_name FROM entity WHERE id=?", [.text(id)]).stringValue) ?? nil
            }
            entityName = entityName ?? (entity["entity_ref"] as? String).flatMap { refNames[$0] ?? $0 }
        } else if let person = dict["object_person"] as? [String: Any] {
            if let id = person["person_id"] as? String {
                entityName = refNames[id]
                    ?? (try? app.store.reader.person(id)?.text("display_name")) ?? nil
            }
            entityName = entityName ?? (person["person_ref"] as? String).flatMap { refNames[$0] ?? $0 }
        }
        let literal = (dict["object_value"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let joined = [entityName, literal].compactMap { $0 }.joined(separator: " — ")
        let object: String? = joined.isEmpty ? nil : joined

        // predicates are snake_case tokens in the ledger; they read as words here
        var line = predicate.replacingOccurrences(of: "_", with: " ")
        if let object { line += " · " + object }
        // an interval's shape is part of the fact: "since 2022" is not "in 2022"
        let from = dict["valid_from"] as? String
        let to = dict["valid_to"] as? String
        switch (from, to) {
        // a fact that opened and closed at the same stated moment is a point in
        // time, not a span — "(2022 – 2022)" reads like a rendering accident
        case let (.some(f), .some(t)) where f == t: line += " (\(f))"
        case let (.some(f), .some(t)): line += " (\(f) – \(t))"
        case let (.some(f), .none):    line += " (since \(f))"
        case let (.none, .some(t)):    line += " (until \(t))"
        case (.none, .none):           break
        }
        return line
    }

    /// The classification the extractor already assigned — `place`, `school`,
    /// `organization` — plus its `part_of` parent when it has one. Both ride in
    /// the payload and neither was ever shown, which made every entity card look
    /// like an unexplained yes/no about a bare name.
    static func entityKindOf(op: ProposalOp, payload: String,
                             refNames: [String: String], app: AppModel) -> String? {
        guard op == .link else { return nil }
        let dict = decode(payload)
        guard let kind = dict["kind"] as? String else { return nil }
        var parent: String?
        if let partOf = dict["part_of"] as? [String: Any] {
            if let id = partOf["entity_id"] as? String {
                parent = (try? app.store.db.scalar(
                    "SELECT canonical_name FROM entity WHERE id=?", [.text(id)]).stringValue) ?? nil
            }
            parent = parent ?? (partOf["entity_ref"] as? String).flatMap { refNames[$0] ?? $0 }
        }
        return Copy.entityKindLine(kind, partOf: parent)
    }

    static func tellerOf(payload: String, app: AppModel) -> String? {
        let dict = decode(payload)
        guard dict["source_kind"] as? String == "secondhand",
              let att = dict["attributed_to"] as? [String: Any],
              let id = att["person_id"] as? String else { return nil }
        return (try? app.store.reader.person(id)?.text("display_name")) ?? nil
    }

    static func questionOf(op: ProposalOp, payload: String) -> String? {
        guard op == .disambiguate else { return nil }
        return decode(payload)["question"] as? String
    }

    /// §7.13: the orbit/intent slots are mapped suggestions SHOWN AS SUCH —
    /// the narrative quote is authoritative, the mapping is editable.
    static func stateSuggestionOf(op: ProposalOp, payload: String) -> String? {
        guard op == .proposeState else { return nil }
        let dict = decode(payload)
        let parts = [dict["suggested_orbit"] as? String,
                     dict["suggested_intent"] as? String].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return Copy.suggestedPrefix + parts.joined(separator: " · ")
    }

    static func candidatesOf(op: ProposalOp, payload: String, app: AppModel) -> [(String, String)] {
        guard op == .disambiguate,
              let list = decode(payload)["candidates"] as? [[String: Any]] else { return [] }
        return list.compactMap { c in
            guard let id = c["person_id"] as? String,
                  let name = try? app.store.reader.person(id)?.text("display_name") else { return nil }
            return (id, name)
        }
    }
}
