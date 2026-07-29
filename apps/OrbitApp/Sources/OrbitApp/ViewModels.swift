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
        text = text.replacingOccurrences(of: suggestion.heard, with: suggestion.candidate)
        nameSuggestions.removeAll { $0 == suggestion }
    }

    func confirm() {
        app?.transcriptConfirmed(eventID: eventID, finalText: text, usedFullModel: usedFullModel)
    }

    func discard() {
        _ = try? app.map { try $0.edits.discardEvent(eventID) }
        app?.pendingCapture = nil
    }
}

/// Proposal review — person-grouped cards (ratified structure, DESIGN §12):
/// quotes light the transcript, settled lines stay visible, "Later" is frictionless.
@MainActor
final class ReviewViewModel: ObservableObject, Identifiable {
    struct Card: Identifiable {
        let id: String
        let op: ProposalOp
        let quote: String            // memory voice, ember-wash left rule
        let rationale: String        // sans — the system explaining itself (P9)
        let hearsayTeller: String?   // hearsay chip when secondhand (§9)
        let question: String?        // DISAMBIGUATE ask-cards
        let candidates: [(id: String, name: String)]
        var settled: String?         // "Saved" / "Skipped" / "Set aside"
    }

    struct PersonGroup: Identifiable {
        let id: String               // person id or ref
        let name: String
        var cards: [Card]
    }

    @Published var groups: [PersonGroup]
    let syncRunID: String
    weak var app: AppModel?
    private let service: ProposalResolutionService

    init(syncRunID: String, app: AppModel) {
        self.syncRunID = syncRunID
        self.app = app
        self.service = app.proposals
        self.groups = Self.load(syncRunID: syncRunID, app: app)
    }

    static func load(syncRunID: String, app: AppModel) -> [PersonGroup] {
        guard let rows = try? app.store.reader.pendingProposals(syncRun: syncRunID) else { return [] }
        var byPerson: [String: PersonGroup] = [:]
        var order: [String] = []
        for row in rows {
            guard let id = row.text("id"), let opRaw = row.text("op"),
                  let op = ProposalOp(rawValue: opRaw),
                  let payload = row.text("payload") else { continue }
            let (personKey, personName) = Self.subjectOf(op: op, payload: payload,
                                                         targetPerson: row.text("target_person_id"),
                                                         app: app)
            let card = Card(
                id: id, op: op,
                quote: Self.quoteOf(op: op, payload: payload),
                rationale: row.text("rationale") ?? "",
                hearsayTeller: Self.tellerOf(payload: payload, app: app),
                question: Self.questionOf(op: op, payload: payload),
                candidates: Self.candidatesOf(op: op, payload: payload, app: app),
                settled: nil)
            if byPerson[personKey] == nil {
                byPerson[personKey] = PersonGroup(id: personKey, name: personName, cards: [])
                order.append(personKey)
            }
            byPerson[personKey]?.cards.append(card)
        }
        return order.compactMap { byPerson[$0] }
    }

    // Decisions — each writes the J-12 outcome row through the funnel.

    func accept(_ card: Card) {
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

    /// Per-person accept-all (ratified interactive behavior).
    func acceptAll(in group: PersonGroup) {
        for card in group.cards where card.settled == nil && card.question == nil {
            accept(card)
        }
    }

    private func settle(_ card: Card, _ op: () throws -> Void) {
        do {
            try op()
            let label: String
            switch card.settled {
            default:
                label = try labelFor(cardID: card.id)
            }
            for gi in groups.indices {
                if let ci = groups[gi].cards.firstIndex(where: { $0.id == card.id }) {
                    groups[gi].cards[ci].settled = label
                }
            }
            app?.refreshAmbient()
        } catch {
            // A dependency error ("accept the person first") surfaces as plain ink,
            // never red (D-1): the card stays unsettled.
        }
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
                          app: AppModel) -> (String, String) {
        let dict = decode(payload)
        func nameOf(_ id: String) -> String {
            (try? app.store.reader.person(id)?.text("display_name")) ?? "…"
        }
        if let target = targetPerson { return (target, nameOf(target)) }
        for key in ["subject", "person"] {
            if let sub = dict[key] as? [String: Any] {
                if let id = sub["person_id"] as? String { return (id, nameOf(id)) }
                if let ref = sub["person_ref"] as? String { return (ref, dict["display_name"] as? String ?? ref) }
            }
        }
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
