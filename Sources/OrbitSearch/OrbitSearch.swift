import Foundation
import OrbitStore
import OrbitSQLite

/// Search & Discover (M4) — one field, three query shapes (ratified, DESIGN §12):
///
///   name     → people anchored by provenance ("met 2023-03 · through Alex"),
///              nicknames and misspellings included (edit distance at query time)
///   question → an ANSWER, not matches: count first, firsthand people with
///              time-bounded evidence, then the visually distinct "And maybe —"
///              band of known-of people, each citing its source
///   fragment → "Probably Nikos — here's why", matched facts as evidence
///
/// Retrieval is FTS5 (porter stemming) over the rm_search read model plus
/// structured passes (entity resolution, introduced_by graph, predicate
/// lookups). Every answer cites its evidence; knows-each-other is derived from
/// the graph, never asserted. Embeddings deliberately absent: the goldens pass
/// without semantic recall, so per BUILD.md the decision is FTS5+structured
/// until a golden demands more (recorded in the WORKLOG).
public struct Searcher {
    let reader: StoreReader

    public init(reader: StoreReader) {
        self.reader = reader
    }

    // MARK: result shapes

    public struct Evidence: Sendable, Equatable {
        public var text: String              // memory voice in the UI
        public var timeBound: String?        // "since 2023-01" — evidence is dated
        public var sourceEventID: String?
    }

    public struct PersonHit: Sendable {
        public var personID: String
        public var name: String
        public var anchor: String            // provenance line, answers which-Sarah
        public var evidence: [Evidence]
    }

    public struct MaybeHit: Sendable {
        public var personID: String
        public var name: String
        public var source: String            // "Alex told you" — every maybe cites its source
        public var evidence: [Evidence]
    }

    public struct Answer: Sendable {
        public var firsthand: [PersonHit]    // count first — the UI leads with firsthand.count
        public var maybe: [MaybeHit]         // the "And maybe —" band
        public var factAnswer: String?       // direct fact lookups ("Google")
    }

    public struct Probably: Sendable {
        public var personID: String
        public var name: String
        public var evidence: [Evidence]      // the search showing its work
    }

    public enum Result: Sendable {
        case people([PersonHit])             // name shape
        case answer(Answer)                  // question shape
        case probably(Probably?, runnersUp: [PersonHit])   // fragment shape
        case empty
    }

    // MARK: entry point

    public func search(_ raw: String) throws -> Result {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .empty }

        if isQuestion(query) {
            return .answer(try answer(query))
        }
        let nameHits = try peopleMatching(nameQuery: query)
        if !nameHits.isEmpty {
            return .people(nameHits)
        }
        let (top, rest) = try fragment(query)
        if top == nil && rest.isEmpty { return .empty }
        return .probably(top, runnersUp: rest)
    }

    func isQuestion(_ q: String) -> Bool {
        let lead = q.lowercased().split(separator: " ").first.map(String.init) ?? ""
        return q.contains("?") || ["who", "where", "what", "when", "which", "how"].contains(lead)
    }

    // MARK: name shape

    /// Direct name search — exact, prefix, and misspelled (distance ≤ 2).
    func peopleMatching(nameQuery: String) throws -> [PersonHit] {
        let tokens = terms(of: nameQuery)
        guard !tokens.isEmpty, tokens.count <= 3 else { return [] }
        let people = try reader.db.query(
            "SELECT id, display_name, COALESCE(preferred_name,'') AS pref FROM person WHERE status != 'merged' AND is_self=0")
        var scored: [(hit: PersonHit, distance: Int)] = []
        for row in people {
            guard let id = row.text("id"), let display = row.text("display_name") else { continue }
            let nameTokens = terms(of: display + " " + (row.text("pref") ?? ""))
            var total = 0
            var matched = true
            for q in tokens {
                let best = nameTokens.map { candidate -> Int in
                    if candidate.hasPrefix(q) { return 0 }
                    return editDistance(q, candidate)
                }.min() ?? Int.max
                if best > 2 { matched = false; break }
                total += best
            }
            if matched {
                scored.append((PersonHit(personID: id, name: display,
                                         anchor: (try? provenanceAnchor(id)) ?? "",
                                         evidence: []), total))
            }
        }
        return scored.sorted { $0.distance < $1.distance }.map(\.hit)
    }

    /// "met 2024-06 · through Alex · last seen 2025-03" — answers which-Sarah.
    func provenanceAnchor(_ personID: String) throws -> String {
        let db = reader.db
        var parts: [String] = []
        if let met = try db.scalar(
            """
            SELECT e.occurred_at FROM person p JOIN event e ON e.id = p.first_met_event_id
            WHERE p.id=?
            """, [.text(personID)]).stringValue {
            parts.append("met \(String(met.prefix(7)))")
        }
        if let via = try db.query(
            """
            SELECT p.display_name FROM rm_network_edge ne JOIN person p ON p.id = ne.from_person
            WHERE ne.to_person=? AND ne.edge_kind='introduced_by' LIMIT 1
            """, [.text(personID)]).first?.text("display_name") {
            parts.append("through \(via)")
        }
        if let seen = try db.scalar(
            """
            SELECT MAX(e.occurred_at) FROM event e
            JOIN event_participant ep ON ep.event_id=e.id
            WHERE ep.person_id=? AND ep.attendance IN ('confirmed','probable') AND e.lifecycle='confirmed'
            """, [.text(personID)]).stringValue {
            parts.append("last seen \(String(seen.prefix(7)))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: question shape

    static let stopwords: Set<String> = [
        "who", "what", "where", "when", "which", "how", "do", "does", "did", "i",
        "know", "at", "in", "the", "a", "an", "is", "are", "was", "with", "of",
        "should", "ask", "about", "can", "me", "to", "my", "for", "have", "has",
    ]

    func answer(_ query: String) throws -> Answer {
        let lower = query.lowercased()

        // "…through <name>" — the provenance/warm-path question
        if let range = lower.range(of: "through ") {
            let name = String(query[range.upperBound...])
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if let via = try peopleMatching(nameQuery: name).first {
                return try throughAnswer(via: via)
            }
        }

        // "where does <name> work / live …" — direct fact lookup
        if let fact = try factLookup(lower: lower, query: query) {
            return fact
        }

        // generic: strip stopwords, retrieve, band by source trust
        let searchTerms = terms(of: lower).filter { !Self.stopwords.contains($0) }
        guard !searchTerms.isEmpty else { return Answer(firsthand: [], maybe: [], factAnswer: nil) }
        return try bandedAnswer(terms: searchTerms)
    }

    /// "Who do I know through Alex?" Firsthand = real introductions (graph,
    /// derived); maybe = known-of people whose facts Alex told him.
    func throughAnswer(via: PersonHit) throws -> Answer {
        let db = reader.db
        var firsthand: [PersonHit] = []
        for r in try db.query(
            """
            SELECT DISTINCT p.id, p.display_name FROM rm_network_edge ne
            JOIN person p ON p.id = ne.to_person
            WHERE ne.from_person=? AND ne.edge_kind='introduced_by' AND p.is_self=0
            """, [.text(via.personID)]) {
            guard let id = r.text("id"), let name = r.text("display_name") else { continue }
            firsthand.append(PersonHit(personID: id, name: name,
                                       anchor: (try? provenanceAnchor(id)) ?? "", evidence: []))
        }
        var maybe: [MaybeHit] = []
        for r in try db.query(
            """
            SELECT DISTINCT p.id, p.display_name, cs.verbatim, cs.source_event_id
            FROM person p
            JOIN rm_current_state cs ON cs.subject_id = p.id
            WHERE p.status='known_of' AND cs.attributed_to_person_id=?
            """, [.text(via.personID)]) {
            guard let id = r.text("id"), let name = r.text("display_name") else { continue }
            maybe.append(MaybeHit(
                personID: id, name: name, source: "\(via.name) told you",
                evidence: [Evidence(text: r.text("verbatim") ?? "", timeBound: nil,
                                    sourceEventID: r.text("source_event_id"))]))
        }
        return Answer(firsthand: firsthand, maybe: maybe, factAnswer: nil)
    }

    static let predicateKeywords: [(keys: [String], predicate: String)] = [
        (["work", "works", "working", "job", "company"], "employment"),
        (["live", "lives", "living", "based", "from"], "location"),
        (["study", "studied", "studying", "school", "degree"], "education"),
    ]

    /// "Where does James work?" → the current fact, with its evidence.
    func factLookup(lower: String, query: String) throws -> Answer? {
        guard let predicate = Self.predicateKeywords.first(where: { pk in
            pk.keys.contains { lower.contains($0) }
        })?.predicate else { return nil }
        // find the person named in the query
        let nameTokens = terms(of: lower)
            .filter { !Self.stopwords.contains($0) }
            .filter { !Self.predicateKeywords.flatMap(\.keys).contains($0) }
        var found: PersonHit?
        for token in nameTokens {
            if let hit = try peopleMatching(nameQuery: token).first { found = hit; break }
        }
        guard let person = found else { return nil }
        let rows = try reader.db.query(
            """
            SELECT cs.assertion_id, cs.verbatim, cs.object_value, cs.valid_from, cs.source_event_id
            FROM rm_current_state cs JOIN assertion a ON a.id = cs.assertion_id
            WHERE cs.subject_id=? AND cs.predicate=? AND a.muted=0
            ORDER BY cs.valid_from DESC
            """, [.text(person.personID), .text(predicate)])
        guard let top = rows.first else {
            return Answer(firsthand: [], maybe: [], factAnswer: nil)
        }
        var hit = person
        hit.evidence = rows.map { r in
            Evidence(text: r.text("verbatim") ?? "",
                     timeBound: r.text("valid_from").map { "since \($0)" },
                     sourceEventID: r.text("source_event_id"))
        }
        return Answer(firsthand: [hit], maybe: [],
                      factAnswer: top.text("object_value") ?? top.text("verbatim"))
    }

    /// Generic question: FTS retrieval + entity structure, banded by trust —
    /// firsthand facts about active people vs. secondhand/known-of ("And maybe —").
    func bandedAnswer(terms searchTerms: [String]) throws -> Answer {
        let rows = try matchedAssertions(terms: searchTerms)

        var firsthand: [String: PersonHit] = [:]
        var maybe: [String: MaybeHit] = [:]
        var order: [String] = []
        for r in rows {
            guard let pid = r.text("subject_id"), let name = r.text("display_name") else { continue }
            let evidence = Evidence(text: r.text("verbatim") ?? "",
                                    timeBound: r.text("valid_from").map { "since \($0)" },
                                    sourceEventID: r.text("source_event_id"))
            let secondhand = r.text("source_kind") == "secondhand" || r.text("status") == "known_of"
            if secondhand {
                if maybe[pid] == nil {
                    let teller = r.text("attributed_to_person_id").flatMap {
                        try? reader.person($0)?.text("display_name")
                    }.flatMap { $0 }
                    maybe[pid] = MaybeHit(personID: pid, name: name,
                                          source: teller.map { "\($0) told you" } ?? "heard secondhand",
                                          evidence: [])
                    order.append("m:" + pid)
                }
                maybe[pid]?.evidence.append(evidence)
            } else {
                if firsthand[pid] == nil {
                    firsthand[pid] = PersonHit(personID: pid, name: name,
                                               anchor: (try? provenanceAnchor(pid)) ?? "",
                                               evidence: [])
                    order.append("f:" + pid)
                }
                firsthand[pid]?.evidence.append(evidence)
            }
        }
        return Answer(
            firsthand: order.filter { $0.hasPrefix("f:") }
                .compactMap { firsthand[String($0.dropFirst(2))] },
            maybe: order.filter { $0.hasPrefix("m:") }
                .compactMap { maybe[String($0.dropFirst(2))] },
            factAnswer: nil)
    }

    /// Current-state rows matching the terms — via FTS on verbatims AND via
    /// entity resolution (alias → object_entity_id), deduplicated.
    func matchedAssertions(terms searchTerms: [String]) throws -> [Row] {
        let db = reader.db
        let match = ftsQuery(searchTerms)
        var rows = try db.query(
            """
            SELECT DISTINCT cs.assertion_id, cs.subject_id, cs.verbatim, cs.valid_from,
                   cs.source_event_id, cs.source_kind, cs.attributed_to_person_id,
                   p.display_name, p.status
            FROM rm_search s
            JOIN rm_current_state cs ON cs.assertion_id = s.ref_id AND s.kind='assertion'
            JOIN person p ON p.id = cs.subject_id
            JOIN assertion a ON a.id = cs.assertion_id
            WHERE rm_search MATCH ? AND a.muted=0
            """, [.text(match)])
        // entity pass: terms that name an entity (or alias) pull its facts too
        for term in searchTerms {
            rows += try db.query(
                """
                SELECT DISTINCT cs.assertion_id, cs.subject_id, cs.verbatim, cs.valid_from,
                       cs.source_event_id, cs.source_kind, cs.attributed_to_person_id,
                       p.display_name, p.status
                FROM entity e
                LEFT JOIN entity_alias al ON al.entity_id = e.id
                JOIN rm_current_state cs ON cs.object_entity_id = e.id
                JOIN person p ON p.id = cs.subject_id
                JOIN assertion a ON a.id = cs.assertion_id
                WHERE (e.canonical_name LIKE ? OR al.alias LIKE ?)
                  AND e.merged_into IS NULL AND a.muted=0
                """, [.text(term), .text(term)])
        }
        var seen = Set<String>()
        return rows.filter { r in
            guard let id = r.text("assertion_id") else { return false }
            return seen.insert(id).inserted
        }
    }

    // MARK: fragment shape

    /// "the guy from Greece at the picnic" → "Probably Nikos — here's why."
    func fragment(_ query: String) throws -> (Probably?, [PersonHit]) {
        let searchTerms = terms(of: query.lowercased()).filter { !Self.stopwords.contains($0) }
        guard !searchTerms.isEmpty else { return (nil, []) }
        let db = reader.db
        let rows = try db.query(
            """
            SELECT s.person_id, s.kind, s.ref_id, s.body, p.display_name
            FROM rm_search s
            JOIN person p ON p.id = s.person_id AND p.is_self=0
            WHERE rm_search MATCH ?
            """, [.text(ftsQuery(searchTerms))])

        struct Agg { var name: String; var atoms: [(kind: String, ref: String, body: String)] = [] }
        var byPerson: [String: Agg] = [:]
        var order: [String] = []
        for r in rows {
            guard let pid = r.text("person_id"), let name = r.text("display_name") else { continue }
            if byPerson[pid] == nil { byPerson[pid] = Agg(name: name); order.append(pid) }
            byPerson[pid]?.atoms.append((r.text("kind") ?? "", r.text("ref_id") ?? "",
                                         r.text("body") ?? ""))
        }
        let ranked = order.sorted {
            (byPerson[$0]?.atoms.count ?? 0) > (byPerson[$1]?.atoms.count ?? 0)
        }
        guard let topID = ranked.first, let top = byPerson[topID] else { return (nil, []) }

        let evidence: [Evidence] = try top.atoms.map { atom in
            switch atom.kind {
            case "assertion":
                let v = try db.scalar("SELECT verbatim FROM rm_current_state WHERE assertion_id=?",
                                      [.text(atom.ref)]).stringValue
                return Evidence(text: v ?? atom.body, timeBound: nil, sourceEventID: nil)
            case "event":
                let t = try db.query(
                    "SELECT COALESCE(title, kind) AS t, occurred_at FROM event WHERE id=?",
                    [.text(atom.ref)]).first
                return Evidence(text: t?.text("t") ?? atom.body,
                                timeBound: t?.text("occurred_at").map { String($0.prefix(7)) },
                                sourceEventID: atom.ref)
            default:
                return Evidence(text: atom.body, timeBound: nil, sourceEventID: nil)
            }
        }
        let runnersUp = ranked.dropFirst().prefix(3).compactMap { pid -> PersonHit? in
            guard let agg = byPerson[pid] else { return nil }
            return PersonHit(personID: pid, name: agg.name,
                             anchor: (try? provenanceAnchor(pid)) ?? "", evidence: [])
        }
        return (Probably(personID: topID, name: top.name, evidence: evidence),
                Array(runnersUp))
    }

    // MARK: text utilities

    func terms(of text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    /// OR-query over sanitized terms; porter stemming happens inside FTS5.
    func ftsQuery(_ searchTerms: [String]) -> String {
        searchTerms.map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1,
                             prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
