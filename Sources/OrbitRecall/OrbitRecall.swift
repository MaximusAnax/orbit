import Foundation
import OrbitStore
import OrbitSQLite

/// Brief assembly — DATA-MODEL §8 made executable.
///
/// There is NO global score anywhere in this file (Decision 7): the Desk is a
/// fixed skeleton and every section runs its own bounded query. Ranking is a
/// query-time function over structural signals — open threads, open loops,
/// change-since-last-contact, `last_surfaced_at`, pinned/muted — and every
/// ranked item carries its *reason* (Principle 9: the ranking can be explained).
///
/// The objective is stated in §8 and implemented literally here: not "what is
/// important" but **what is he most likely to have forgotten** — never-surfaced
/// first, then longest-unsurfaced, then oldest-known.
public struct Brief: Sendable {
    public struct Header: Sendable {
        public var personID: String
        public var name: String
        public var metLine: String          // "met-when · through-whom · last-seen"
    }
    public struct Hero: Sendable {
        public var assertionID: String
        public var claim: String            // verbatim — memory voice
        public var reason: String           // sans rationale — the explainable ranking
        public var pinned: Bool
    }
    public struct ThreadItem: Sendable {
        public var id: String
        public var title: String
        public var statusLine: String       // staleness displayed, not hidden (§9.1)
        public var promptState: String      // active | context_only
        public var isHardship: Bool         // renders as context, never a suggested opener
    }
    public struct LoopItem: Sendable {
        public var id: String
        public var description: String
        public var tag: String              // "You owe" / "Owed to you"
    }
    public struct ChangeItem: Sendable {
        public var assertionID: String
        public var line: String             // verbatim (or "no longer: …" for closes)
        public var isClose: Bool
    }
    public struct ForgottenItem: Sendable {
        public var assertionID: String
        public var claim: String
        public var eraLabel: String         // era grouping keeps 40 items reading as a story
        public var reason: String
    }
    public struct TimelineSummary: Sendable {
        public var eventCount: Int
        public var sinceYear: String?       // "14 events since 2023"
    }
    public struct ReachItem: Sendable {
        public var kind: String
        public var value: String
    }

    public var header: Header
    public var hero: Hero?                  // tile 2 — exactly one item
    public var openThreads: [ThreadItem]    // tile 3 — top + count rendered by UI
    public var loops: [LoopItem]            // tile 4
    public var changed: [ChangeItem]        // tile 5
    public var forgotten: [ForgottenItem]   // tile 6 — UNBOUNDED by ratified decision
    public var timeline: TimelineSummary    // tile 7
    public var reach: [ReachItem]           // tile 8
    public var lastSeenAt: String?

    /// The "Walk me in" pill hides on near-empty profiles (DESIGN §6.1 tile 1).
    public var deckAvailable: Bool {
        var tiles = 0
        if hero != nil { tiles += 1 }
        if !openThreads.isEmpty { tiles += 1 }
        if !loops.isEmpty { tiles += 1 }
        if !changed.isEmpty { tiles += 1 }
        if !forgotten.isEmpty { tiles += 1 }
        return tiles >= 3
    }
}

public struct BriefAssembler {
    let reader: StoreReader

    public init(reader: StoreReader) {
        self.reader = reader
    }

    public func assemble(personID rawID: String, now: String) throws -> Brief {
        let personID = try reader.canonicalPerson(rawID)
        let db = reader.db

        guard let person = try reader.person(personID) else {
            throw SQLiteError(code: -1, message: "no such person \(personID)")
        }
        let name = person.text("display_name") ?? "…"

        // last seen: most recent confirmed event actually attended together —
        // `about` never counts as contact (INV-11)
        let lastSeen = try db.scalar(
            """
            SELECT MAX(e.occurred_at) FROM event e
            JOIN event_participant ep ON ep.event_id = e.id
            WHERE ep.person_id=? AND ep.attendance IN ('confirmed','probable')
              AND e.lifecycle='confirmed' AND e.derived_from_event_id IS NULL
            """, [.text(personID)]).stringValue

        let header = Brief.Header(
            personID: personID, name: name,
            metLine: try metLine(personID: personID, person: person, lastSeen: lastSeen, db: db))

        // ── current-state pool with the human-override columns (§8 signal 6):
        // muted rows never leave this query; everything downstream is clean of them
        let pool = try db.query(
            """
            SELECT cs.assertion_id, cs.predicate, cs.verbatim, cs.valid_from, cs.observed_at,
                   cs.source_kind, a.last_surfaced_at, a.pinned
            FROM rm_current_state cs
            JOIN assertion a ON a.id = cs.assertion_id
            WHERE cs.subject_id=? AND a.muted=0
            ORDER BY (a.pinned=1) DESC,
                     (a.last_surfaced_at IS NULL) DESC,
                     a.last_surfaced_at ASC,
                     cs.observed_at ASC,
                     cs.assertion_id ASC
            """, [.text(personID)])

        // hero: pinned wins outright; else the top of the forgotten-ranking
        var hero: Brief.Hero?
        if let top = pool.first {
            let pinned = top.int("pinned") == 1
            hero = Brief.Hero(
                assertionID: top.text("assertion_id") ?? "",
                claim: top.text("verbatim") ?? "",
                reason: pinned ? "You pinned this."
                    : heroReason(lastSurfaced: top.text("last_surfaced_at"),
                                 observedAt: top.text("observed_at") ?? "", now: now),
                pinned: pinned)
        }

        // ── open threads, staleness displayed (§9.1); hardship = context only
        let threadRows = try db.query(
            """
            SELECT id, title, archetype, prompt_state, last_mentioned_at,
                   conversations_since_mention, expected_resolution_at
            FROM thread WHERE person_id=? AND state='open'
            ORDER BY (prompt_state='active') DESC, last_mentioned_at DESC
            """, [.text(personID)])
        let openThreads = threadRows.map { r in
            Brief.ThreadItem(
                id: r.text("id") ?? "",
                title: r.text("title") ?? "",
                statusLine: threadStatus(r, now: now),
                promptState: r.text("prompt_state") ?? "active",
                isHardship: r.text("archetype") == "condition_hardship")
        }

        // ── open loops, both directions (§8 signal 2)
        let loops = try db.query(
            """
            SELECT id, direction, description FROM open_loop
            WHERE person_id=? AND state='open' ORDER BY due_at IS NULL, due_at
            """, [.text(personID)]).map { r in
            Brief.LoopItem(id: r.text("id") ?? "",
                           description: r.text("description") ?? "",
                           tag: r.text("direction") == "abdoul_owes" ? "You owe" : "Owed to you")
        }

        // ── changed since last seen (§8 signal 3): new facts + closed facts
        var changed: [Brief.ChangeItem] = []
        if let lastSeen {
            for r in pool where (r.text("observed_at") ?? "") > lastSeen {
                changed.append(.init(assertionID: r.text("assertion_id") ?? "",
                                     line: r.text("verbatim") ?? "", isClose: false))
            }
            for r in try db.query(
                """
                SELECT a.id, a.verbatim FROM assertion a
                WHERE a.subject_id=? AND a.superseded_by IS NULL AND a.muted=0
                  AND a.valid_to IS NOT NULL AND a.observed_at > ?
                """, [.text(personID), .text(lastSeen)]) {
                changed.append(.init(assertionID: r.text("id") ?? "",
                                     line: "no longer: \(r.text("verbatim") ?? "")", isClose: true))
            }
        }

        // ── worth having back (§8 signal 4, the signature): deliberately
        // unbounded — truncation would discard exactly what the product exists
        // to return; era labels keep forty items reading as a story
        let heroID = hero?.assertionID
        let changedIDs = Set(changed.map(\.assertionID))
        let metYear = try firstMetYear(personID: personID, person: person, db: db)
        let forgotten: [Brief.ForgottenItem] = pool
            .filter {
                let id = $0.text("assertion_id")
                // each item lives in exactly one section: hero and "changed"
                // rows don't repeat here
                return id != heroID && $0.int("pinned") != 1
                    && !changedIDs.contains(id ?? "")
            }
            .map { r in
                let year = String((r.text("valid_from") ?? r.text("observed_at") ?? "").prefix(4))
                return Brief.ForgottenItem(
                    assertionID: r.text("assertion_id") ?? "",
                    claim: r.text("verbatim") ?? "",
                    eraLabel: year == metYear ? "when you first met" : year,
                    reason: heroReason(lastSurfaced: r.text("last_surfaced_at"),
                                       observedAt: r.text("observed_at") ?? "", now: now))
            }

        // ── timeline row: a real count, never rounded (D-9)
        let events = try db.query(
            """
            SELECT COUNT(*) AS n, MIN(occurred_at) AS first FROM event e
            JOIN event_participant ep ON ep.event_id = e.id
            WHERE ep.person_id=? AND e.lifecycle='confirmed'
            """, [.text(personID)]).first
        let timeline = Brief.TimelineSummary(
            eventCount: Int(events?.int("n") ?? 0),
            sinceYear: (events?.text("first")).map { String($0.prefix(4)) })

        // ── reach: current contact points
        let reach = try db.query(
            """
            SELECT kind, value FROM contact_point
            WHERE person_id=? AND valid_to IS NULL ORDER BY is_primary DESC, kind
            """, [.text(personID)]).map {
            Brief.ReachItem(kind: $0.text("kind") ?? "", value: $0.text("value") ?? "")
        }

        return Brief(header: header, hero: hero, openThreads: openThreads, loops: loops,
                     changed: changed, forgotten: forgotten, timeline: timeline,
                     reach: reach, lastSeenAt: lastSeen)
    }

    // MARK: helpers

    func metLine(personID: String, person: Row, lastSeen: String?, db: Database) throws -> String {
        var parts: [String] = []
        if let metEvent = person.text("first_met_event_id"),
           let when = try db.scalar("SELECT occurred_at FROM event WHERE id=?",
                                    [.text(metEvent)]).stringValue {
            parts.append("met \(String(when.prefix(7)))")
        }
        if let via = try db.query(
            """
            SELECT p.display_name FROM rm_network_edge ne
            JOIN person p ON p.id = ne.to_person
            WHERE ne.from_person=? AND ne.edge_kind='introduced_by' LIMIT 1
            """, [.text(personID)]).first?.text("display_name") {
            parts.append("through \(via)")
        }
        if let lastSeen {
            parts.append("last seen \(String(lastSeen.prefix(10)))")
        }
        return parts.joined(separator: " · ")
    }

    func firstMetYear(personID: String, person: Row, db: Database) throws -> String {
        if let metEvent = person.text("first_met_event_id"),
           let when = try db.scalar("SELECT occurred_at FROM event WHERE id=?",
                                    [.text(metEvent)]).stringValue {
            return String(when.prefix(4))
        }
        let earliest = try db.scalar(
            """
            SELECT MIN(e.occurred_at) FROM event e
            JOIN event_participant ep ON ep.event_id = e.id
            WHERE ep.person_id=? AND e.lifecycle='confirmed'
            """, [.text(personID)]).stringValue
        return String((earliest ?? "").prefix(4))
    }

    /// Principle 9: the reason travels with the item, in plain words.
    func heroReason(lastSurfaced: String?, observedAt: String, now: String) -> String {
        guard let lastSurfaced else {
            let year = String(observedAt.prefix(4))
            return year.isEmpty ? "Never shown to you before."
                : "From \(year) — never shown to you before."
        }
        return "Last shown \(String(lastSurfaced.prefix(10)))."
    }

    /// Staleness displayed, not hidden (§9.1): "2 years ago, never came up again".
    func threadStatus(_ r: Row, now: String) -> String {
        let convs = Int(r.int("conversations_since_mention") ?? 0)
        let mentioned = r.text("last_mentioned_at").map { String($0.prefix(10)) }
        var line = mentioned.map { "last mentioned \($0)" } ?? "never mentioned since"
        if convs > 0 {
            line += " · \(convs) conversation\(convs == 1 ? "" : "s") since"
        }
        if r.text("prompt_state") == "context_only" {
            line += " · context now"
        }
        return line
    }
}

// MARK: - The Deck ("Walk me in", DESIGN §7)

/// Card order = Desk order — the Deck teaches the Desk's map. 5–7 cards; the
/// Deck SELECTS, it never paginates the profile. Ends on the tool's one
/// memory-voice sentence.
public struct Deck: Sendable {
    public struct Card: Sendable {
        public var tag: String        // ember caps
        public var main: String       // serif 24px
        public var sub: String        // sans
        public var surfacedAssertionID: String?   // deck sessions write last_surfaced_at
        public var isEnd: Bool = false
    }
    public var cards: [Card]

    /// Assertion ids shown by this deck — the caller records them through the
    /// write funnel (OrbitWrite.markSurfaced; INV-5 keeps this module read-only).
    public var surfacedAssertionIDs: [String] {
        cards.compactMap(\.surfacedAssertionID)
    }

    public static func build(from brief: Brief) -> Deck {
        var cards: [Card] = []
        if let hero = brief.hero {
            cards.append(Card(tag: "If you remember one thing", main: hero.claim,
                              sub: hero.reason, surfacedAssertionID: hero.assertionID))
        }
        // hardship threads are context, never suggested openers (PIPE-14):
        // the tag and sub-line frame what's going on, not what to ask
        if let thread = brief.openThreads.first {
            cards.append(Card(
                tag: thread.isHardship ? "Context" : "Open",
                main: thread.title,
                sub: thread.isHardship ? "For context — let them bring it up. \(thread.statusLine)"
                                       : thread.statusLine,
                surfacedAssertionID: nil))
        }
        if let loop = brief.loops.first {
            cards.append(Card(tag: loop.tag, main: loop.description, sub: "",
                              surfacedAssertionID: nil))
        }
        if let change = brief.changed.first {
            cards.append(Card(tag: "Since you last saw them", main: change.line,
                              sub: "", surfacedAssertionID: change.assertionID))
        }
        for item in brief.forgotten.prefix(2) where cards.count < 6 {
            cards.append(Card(tag: "Worth having back", main: item.claim,
                              sub: item.reason, surfacedAssertionID: item.assertionID))
        }
        cards.append(Card(tag: "That's everything", main: "Go be present.",
                          sub: "", surfacedAssertionID: nil, isEnd: true))
        return Deck(cards: cards)
    }
}
