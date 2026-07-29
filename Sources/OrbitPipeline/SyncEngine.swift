import Foundation
import OrbitCore
import OrbitSQLite
import OrbitStore
import OrbitWrite

/// Turns an ExtractionPayload into pending proposals through the write funnel.
/// Everything lands `pending` (INV-5/6); the engine's job is faithful transport
/// plus the §7 policy rules — it adds no judgment of its own beyond them.
public struct SyncEngine {
    let store: WriteStore
    let proposals: ProposalResolutionService

    public init(_ store: WriteStore) {
        self.store = store
        self.proposals = ProposalResolutionService(store)
    }

    public struct Outcome: Sendable {
        public var syncRunID: String
        public var proposalIDs: [String]
        public var suppressedCount: Int   // INV-7 same-source drops
    }

    /// Register the extraction and emit proposals for the given event.
    @discardableResult
    public func sync(event: String, extractionVersion: Int, result: ExtractionResult) throws -> Outcome {
        let reader = store.reader
        let selfID = try reader.selfPerson()?.text("id")

        let payloadJSON = try PayloadCoding.encode(result.payload)
        let extraction = try proposals.recordExtraction(
            event: event, version: extractionVersion, modelID: result.modelID,
            promptVersion: result.promptVersion, payload: payloadJSON,
            ambiguities: try PayloadCoding.encode(result.payload.ambiguities))
        let run = try proposals.openSyncRun(event: event, extraction: extraction)

        var ids: [String] = []
        var suppressed = 0
        func emit(_ draft: ProposalResolutionService.Draft) throws {
            if let id = try proposals.propose(syncRun: run, draft) {
                ids.append(id)
            } else {
                suppressed += 1
            }
        }

        // Resolve a payload subject_ref to a PersonRef for OrbitWrite payloads.
        // "self" targets the self row (INV-22: never a newly created person).
        var refKinds: [String: ExtractionPayload.PersonMention] = [:]
        for p in result.payload.people { refKinds[p.ref] = p }

        func personRef(_ ref: String) throws -> PersonRef {
            if ref == "self" {
                guard let selfID else {
                    throw WriteError.invalidState("no self row exists; run onboarding first (INV-22)")
                }
                return .id(selfID)
            }
            if let mention = refKinds[ref] {
                switch mention.match {
                case "existing":
                    if let id = mention.existingPersonID { return .id(id) }
                    return .ref(ref)
                case "self":
                    guard let selfID else {
                        throw WriteError.invalidState("no self row exists (INV-22)")
                    }
                    return .id(selfID)
                default:
                    return .ref(ref)   // materialized by that person's CREATE_PERSON card
                }
            }
            return .ref(ref)
        }

        // 1. People — CREATE_PERSON for new; DISAMBIGUATE for murky or namesake
        //    collisions (§7.7: no branch guesses silently).
        for person in result.payload.people {
            switch person.match {
            case "new":
                try emit(.init(
                    op: .createPerson,
                    payloadJSON: try PayloadCoding.encode(CreatePersonPayload(
                        ref: person.ref, displayName: person.nameAsHeard, status: person.status)),
                    rationale: person.matchRationale ?? "new person mentioned in this capture"))
            case "ambiguous", "self_collision":
                // surfaced through the matching ambiguity entry below; no silent row
                continue
            default:
                continue   // existing/self: nothing to create
            }
        }

        // 2. Entities — LINK to existing or create-new, reviewed either way (§7.10).
        // DB alias matching happens HERE too, so a context primer miss cannot
        // fragment identity (PIPE-13): spoken name or alias matching a stored
        // alias/canonical name → link, not create.
        func aliasMatch(_ mention: ExtractionPayload.EntityMention) throws -> String? {
            if let id = mention.existingEntityID { return id }
            for candidate in [mention.nameAsHeard] + mention.aliases {
                if let id = try store.db.scalar(
                    """
                    SELECT e.id FROM entity e
                    LEFT JOIN entity_alias a ON a.entity_id = e.id
                    WHERE e.canonical_name = ? COLLATE NOCASE OR a.alias = ? COLLATE NOCASE
                    LIMIT 1
                    """, [.text(candidate), .text(candidate)]).stringValue {
                    return id
                }
            }
            return nil
        }
        for entity in result.payload.entities {
            let partOf: EntityRef? = entity.partOfRef.map { ref in
                if let existing = result.payload.entities.first(where: { $0.ref == ref }),
                   let id = existing.existingEntityID {
                    return .id(id)
                }
                return .ref(ref)
            }
            let matchedID = try aliasMatch(entity)
            try emit(.init(
                op: .link,
                payloadJSON: try PayloadCoding.encode(LinkEntityPayload(
                    ref: entity.ref, existingEntityID: matchedID,
                    kind: entity.kind, canonicalName: entity.nameAsHeard,
                    partOf: partOf, aliases: [entity.nameAsHeard] + entity.aliases)),
                rationale: matchedID != nil
                    ? "matches known entity; adds spoken variant as alias"
                    : "new context mentioned in this capture"))
        }

        // 3. Threads (before assertions so thread_ref joins resolve on acceptance).
        for thread in result.payload.threads {
            let archetype = ThreadArchetype(rawValue: thread.archetype) ?? .aspiration
            try emit(.init(
                op: .openThread,
                payloadJSON: try PayloadCoding.encode(OpenThreadPayload(
                    ref: thread.ref, person: try personRef(thread.subjectRef),
                    title: thread.title, archetype: archetype.rawValue,
                    expectedResolutionAt: thread.expectedResolutionAt,
                    expectedResolutionPrecision: thread.expectedResolutionPrecision)),
                rationale: "open situation: \u{201C}\(thread.evidenceVerbatim)\u{201D}"))
        }

        // 4. §9.4 implicit thread resolution — proposed, never applied.
        for closure in result.payload.threadClosures {
            try emit(.init(
                op: .closeThread,
                payloadJSON: try PayloadCoding.encode(CloseThreadPayload(
                    threadID: closure.threadID, resolutionNote: closure.resolutionNote)),
                rationale: "this seems to resolve an open thread: \u{201C}\(closure.evidenceVerbatim)\u{201D}"))
        }

        // 5. Assertions — including CLOSE proposals when an open fact is contradicted.
        for draft in result.payload.assertions {
            let subject = try personRef(draft.subjectRef)
            let assertPayload = AssertPayload(
                subject: subject,
                predicate: draft.predicate,
                objectEntity: draft.objectEntityRef.flatMap { ref in
                    result.payload.entities.first(where: { $0.ref == ref })
                        .flatMap { $0.existingEntityID.map(EntityRef.id) } ?? .ref(ref)
                },
                objectPerson: try draft.objectPersonRef.map { try personRef($0) },
                objectValue: draft.objectValue,
                verbatim: draft.verbatim,
                validFrom: draft.validFrom,
                validTo: draft.validTo,
                datePrecision: draft.datePrecision,
                sourceKind: draft.sourceKind,
                attributedTo: try draft.attributedToRef.map { try personRef($0) },
                confidence: draft.confidence ?? (draft.hedged ? 0.5 : nil),
                threadRef: draft.threadRef)
            let hedgeNote = draft.hedged ? " (speaker hedged — kept tentative)" : ""
            try emit(.init(
                op: .assert,
                payloadJSON: try PayloadCoding.encode(assertPayload),
                rationale: "\u{201C}\(draft.verbatim)\u{201D}\(hedgeNote)"))

            // Contradiction of a currently-open fact → CLOSE proposal, never overwrite.
            if case .id(let subjectID) = subject,
               draft.validTo == nil,
               ["employment", "location", "education"].contains(draft.predicate) {
                let open = try store.reader.currentState(of: subjectID)
                    .filter { $0.text("predicate") == draft.predicate
                           && $0.text("object_value") != draft.objectValue }
                for fact in open {
                    try emit(.init(
                        op: .close,
                        payloadJSON: try PayloadCoding.encode(ClosePayload(
                            validTo: draft.validFrom ?? eventDate(event),
                            verbatim: draft.verbatim)),
                        rationale: "\u{201C}\(draft.verbatim)\u{201D} supersedes \u{201C}\(fact.text("verbatim") ?? "")\u{201D} — the old fact closes, it is not deleted",
                        targetAssertion: fact.text("assertion_id")))
                }
            }
        }

        // 5b. Corrections (Decision 2): never_true → CORRECT; no_longer_true → CLOSE.
        for correction in result.payload.corrections {
            guard case .id(let subjectID) = try personRef(correction.subjectRef) else { continue }
            let like = "%" + correction.objectLike.lowercased() + "%"
            let targets = try store.db.query(
                """
                SELECT assertion_id, verbatim FROM rm_current_state
                WHERE subject_id=? AND predicate=?
                  AND (LOWER(COALESCE(object_value,'')) LIKE ? OR LOWER(verbatim) LIKE ?)
                """, [.text(subjectID), .text(correction.predicate), .text(like), .text(like)])
            for t in targets {
                if correction.kind == "never_true" {
                    try emit(.init(
                        op: .correct,
                        payloadJSON: try PayloadCoding.encode(CorrectPayload(
                            reason: correction.verbatim)),
                        rationale: "you said this was never true: \u{201C}\(correction.verbatim)\u{201D} — it will be retracted, not deleted",
                        targetAssertion: t.text("assertion_id")))
                } else {
                    try emit(.init(
                        op: .close,
                        payloadJSON: try PayloadCoding.encode(ClosePayload(
                            validTo: correction.validTo ?? eventDate(event),
                            verbatim: correction.verbatim)),
                        rationale: "\u{201C}\(correction.verbatim)\u{201D} — the fact was true and stopped being true",
                        targetAssertion: t.text("assertion_id")))
                }
            }
        }

        // 6. Episodes — CREATE_EVENT reconstructions (portraits, §7.11).
        for episode in result.payload.episodes {
            let hedge = episode.hedged ? " — the source hedges this" : ""
            try emit(.init(
                op: .createEvent,
                payloadJSON: try PayloadCoding.encode(CreateEventPayload(
                    occurredAt: episode.occurredAt,
                    datePrecision: episode.datePrecision,
                    kind: episode.kind,
                    title: episode.title,
                    narrative: episode.narrative,
                    participants: try episode.participantRefs.map {
                        .init(person: try personRef($0), attendance: "confirmed")
                    })),
                rationale: "a remembered episode (\(episode.eraRelative ?? episode.occurredAt))\(hedge)"))
        }

        // 7. Loops.
        for loop in result.payload.loops {
            try emit(.init(
                op: .openLoop,
                payloadJSON: try PayloadCoding.encode(OpenLoopPayload(
                    person: try personRef(loop.subjectRef), direction: loop.direction,
                    description: loop.description, dueAt: loop.dueAt,
                    duePrecision: loop.duePrecision)),
                rationale: "\u{201C}\(loop.verbatim)\u{201D}"))
        }

        // 8. Contact points (voice-derived → unverified rendering, §7.8).
        for cp in result.payload.contactPoints {
            try emit(.init(
                op: .contactPoint,
                payloadJSON: try PayloadCoding.encode(ContactPointPayload(
                    person: try personRef(cp.subjectRef), kind: cp.kind,
                    value: cp.value, source: "voice")),
                rationale: "\u{201C}\(cp.verbatim)\u{201D} — voice-derived, unverified until first used"))
        }

        // 9. Relationship-state transport (§7.13; INV-24 enforced at the funnel).
        for decl in result.payload.stateDeclarations {
            do {
                try emit(.init(
                    op: .proposeState,
                    payloadJSON: try PayloadCoding.encode(ProposeStatePayload(
                        person: try personRef(decl.subjectRef),
                        narrativeQuote: decl.quote,
                        suggestedOrbit: decl.suggestedOrbit,
                        suggestedIntent: decl.suggestedIntent,
                        mappingRationale: decl.mappingRationale)),
                    rationale: "your words, carried over for review: \u{201C}\(decl.quote)\u{201D}"))
            } catch WriteError.constitutionViolation {
                // INV-24 held: no verbatim quote, no proposal — the model tried
                // to infer state and the funnel refused. The rest of the memo's
                // sync proceeds; losing the whole review over one refused op
                // would punish the user for the model's overreach.
            }
        }

        // 10. Ambiguities → DISAMBIGUATE cards ("Was this James?" — §11).
        for amb in result.payload.ambiguities {
            let candidates: [PersonRef] = try amb.candidateRefs.map { try personRef($0) }
            let held: AssertPayload
            if let a = amb.assertion {
                held = AssertPayload(
                    subject: .ref("unresolved"), predicate: a.predicate,
                    objectValue: a.objectValue, verbatim: a.verbatim,
                    datePrecision: a.datePrecision, sourceKind: a.sourceKind,
                    confidence: a.confidence ?? 0.5)
            } else {
                held = AssertPayload(subject: .ref("unresolved"), predicate: "trait",
                                     objectValue: nil, verbatim: amb.question,
                                     datePrecision: "fuzzy")
            }
            try emit(.init(
                op: .disambiguate,
                payloadJSON: try PayloadCoding.encode(DisambiguatePayload(
                    question: amb.question, candidates: candidates, assertion: held)),
                rationale: "uncertain \(amb.kind) — asking rather than guessing (P4)"))
        }

        // §7.3: a known_of person present at THIS event → promote + flag for
        // reconfirmation (structural, not a proposal — meeting someone is a fact).
        let present = try store.db.query(
            """
            SELECT p.id FROM event_participant ep
            JOIN person p ON p.id = ep.person_id
            WHERE ep.event_id=? AND ep.attendance IN ('confirmed','probable')
              AND p.status IN ('known_of')
            """, [.text(event)])
        for row in present {
            try proposals.promoteOnFirstMeeting(person: row.text("id")!)
        }

        try proposals.completeSyncRun(run)
        return Outcome(syncRunID: run, proposalIDs: ids, suppressedCount: suppressed)
    }

    func eventDate(_ id: String) -> String {
        (try? store.db.scalar("SELECT occurred_at FROM event WHERE id=?", [.text(id)]).stringValue ?? "")
            ?? ""
    }
}
