import Foundation
import OrbitCore

/// The structured output contract of the extraction endpoint (§7.9 seam).
/// This exact JSON shape is what the LLM returns, what fixtures record, and what
/// the goldens grade — one schema across production, replay, and evals.
public struct ExtractionPayload: Codable, Sendable {
    public var people: [PersonMention]
    public var entities: [EntityMention]
    public var assertions: [AssertionDraft]
    public var episodes: [EpisodeDraft]           // portraits only (§7.11)
    public var threads: [ThreadDraft]
    public var threadClosures: [ThreadClosureDraft]
    public var loops: [LoopDraft]
    public var contactPoints: [ContactPointDraft]
    public var stateDeclarations: [StateDeclaration]
    public var corrections: [CorrectionDraft]
    public var ambiguities: [Ambiguity]

    enum CodingKeys: String, CodingKey {
        case people, entities, assertions, episodes, threads
        case threadClosures = "thread_closures"
        case loops
        case contactPoints = "contact_points"
        case stateDeclarations = "state_declarations"
        case corrections, ambiguities
    }

    public init(people: [PersonMention] = [], entities: [EntityMention] = [],
                assertions: [AssertionDraft] = [], episodes: [EpisodeDraft] = [],
                threads: [ThreadDraft] = [], threadClosures: [ThreadClosureDraft] = [],
                loops: [LoopDraft] = [], contactPoints: [ContactPointDraft] = [],
                stateDeclarations: [StateDeclaration] = [], corrections: [CorrectionDraft] = [],
                ambiguities: [Ambiguity] = []) {
        self.people = people
        self.entities = entities
        self.assertions = assertions
        self.episodes = episodes
        self.threads = threads
        self.threadClosures = threadClosures
        self.loops = loops
        self.contactPoints = contactPoints
        self.stateDeclarations = stateDeclarations
        self.corrections = corrections
        self.ambiguities = ambiguities
    }

    /// §7.7: how a mentioned name maps onto identity — never silently (Principle 4).
    public struct PersonMention: Codable, Sendable {
        public var ref: String
        public var nameAsHeard: String
        /// new | existing | ambiguous | self | self_collision
        public var match: String
        public var existingPersonID: String?
        public var matchRationale: String?
        /// active | provisional | known_of — known_of when only ever heard about (§7.3)
        public var status: String
        enum CodingKeys: String, CodingKey {
            case ref
            case nameAsHeard = "name_as_heard"
            case match
            case existingPersonID = "existing_person_id"
            case matchRationale = "match_rationale"
            case status
        }
        public init(ref: String, nameAsHeard: String, match: String,
                    existingPersonID: String? = nil, matchRationale: String? = nil,
                    status: String = "active") {
            self.ref = ref
            self.nameAsHeard = nameAsHeard
            self.match = match
            self.existingPersonID = existingPersonID
            self.matchRationale = matchRationale
            self.status = status
        }
    }

    /// §7.10: strings never carry identity — every context becomes an entity ref.
    public struct EntityMention: Codable, Sendable {
        public var ref: String
        public var nameAsHeard: String
        public var kind: String
        public var existingEntityID: String?
        public var partOfRef: String?
        public var aliases: [String]
        enum CodingKeys: String, CodingKey {
            case ref
            case nameAsHeard = "name_as_heard"
            case kind
            case existingEntityID = "existing_entity_id"
            case partOfRef = "part_of_ref"
            case aliases
        }
        public init(ref: String, nameAsHeard: String, kind: String,
                    existingEntityID: String? = nil, partOfRef: String? = nil,
                    aliases: [String] = []) {
            self.ref = ref
            self.nameAsHeard = nameAsHeard
            self.kind = kind
            self.existingEntityID = existingEntityID
            self.partOfRef = partOfRef
            self.aliases = aliases
        }
    }

    public struct AssertionDraft: Codable, Sendable {
        public var subjectRef: String            // person ref, or "self" (§7.12)
        public var predicate: String
        public var objectEntityRef: String?
        public var objectPersonRef: String?
        public var objectValue: String?
        public var verbatim: String              // exact substring of the transcript (PIPE-6)
        public var validFrom: String?
        public var validTo: String?
        public var datePrecision: String
        public var sourceKind: String
        public var attributedToRef: String?
        public var hedged: Bool                  // PIPE-5: every "I think/maybe/probably" survives
        public var confidence: Double?
        public var threadRef: String?
        enum CodingKeys: String, CodingKey {
            case subjectRef = "subject_ref"
            case predicate
            case objectEntityRef = "object_entity_ref"
            case objectPersonRef = "object_person_ref"
            case objectValue = "object_value"
            case verbatim
            case validFrom = "valid_from"
            case validTo = "valid_to"
            case datePrecision = "date_precision"
            case sourceKind = "source_kind"
            case attributedToRef = "attributed_to_ref"
            case hedged, confidence
            case threadRef = "thread_ref"
        }
        public init(subjectRef: String, predicate: String, objectEntityRef: String? = nil,
                    objectPersonRef: String? = nil,
                    objectValue: String? = nil, verbatim: String, validFrom: String? = nil,
                    validTo: String? = nil, datePrecision: String = "fuzzy",
                    sourceKind: String = "firsthand", attributedToRef: String? = nil,
                    hedged: Bool = false, confidence: Double? = nil, threadRef: String? = nil) {
            self.subjectRef = subjectRef
            self.predicate = predicate
            self.objectEntityRef = objectEntityRef
            self.objectPersonRef = objectPersonRef
            self.objectValue = objectValue
            self.verbatim = verbatim
            self.validFrom = validFrom
            self.validTo = validTo
            self.datePrecision = datePrecision
            self.sourceKind = sourceKind
            self.attributedToRef = attributedToRef
            self.hedged = hedged
            self.confidence = confidence
            self.threadRef = threadRef
        }
    }

    /// A past occurrence with a what and a when-ish (PIPE-12 bar).
    public struct EpisodeDraft: Codable, Sendable {
        public var occurredAt: String
        public var datePrecision: String
        public var eraRelative: String?          // e.g. "sophomore spring" — resolved against stated anchors only
        public var kind: String
        public var title: String
        public var narrative: String             // the verbatim slice of the portrait
        public var participantRefs: [String]     // present people (they genuinely were there)
        public var isMetEvent: Bool
        public var hedged: Bool
        enum CodingKeys: String, CodingKey {
            case occurredAt = "occurred_at"
            case datePrecision = "date_precision"
            case eraRelative = "era_relative"
            case kind, title, narrative
            case participantRefs = "participant_refs"
            case isMetEvent = "is_met_event"
            case hedged
        }
        public init(occurredAt: String, datePrecision: String, eraRelative: String? = nil,
                    kind: String, title: String, narrative: String, participantRefs: [String],
                    isMetEvent: Bool = false, hedged: Bool = false) {
            self.occurredAt = occurredAt
            self.datePrecision = datePrecision
            self.eraRelative = eraRelative
            self.kind = kind
            self.title = title
            self.narrative = narrative
            self.participantRefs = participantRefs
            self.isMetEvent = isMetEvent
            self.hedged = hedged
        }
    }

    public struct ThreadDraft: Codable, Sendable {
        public var ref: String
        public var subjectRef: String
        public var title: String
        public var archetype: String
        public var expectedResolutionAt: String?
        public var expectedResolutionPrecision: String?
        public var evidenceVerbatim: String
        enum CodingKeys: String, CodingKey {
            case ref
            case subjectRef = "subject_ref"
            case title, archetype
            case expectedResolutionAt = "expected_resolution_at"
            case expectedResolutionPrecision = "expected_resolution_precision"
            case evidenceVerbatim = "evidence_verbatim"
        }
        public init(ref: String, subjectRef: String, title: String, archetype: String,
                    expectedResolutionAt: String? = nil, expectedResolutionPrecision: String? = nil,
                    evidenceVerbatim: String) {
            self.ref = ref
            self.subjectRef = subjectRef
            self.title = title
            self.archetype = archetype
            self.expectedResolutionAt = expectedResolutionAt
            self.expectedResolutionPrecision = expectedResolutionPrecision
            self.evidenceVerbatim = evidenceVerbatim
        }
    }

    /// §9.4: a new statement fulfilled/contradicted an open thread's premise.
    public struct ThreadClosureDraft: Codable, Sendable {
        public var threadID: String
        public var resolutionNote: String
        public var evidenceVerbatim: String
        enum CodingKeys: String, CodingKey {
            case threadID = "thread_id"
            case resolutionNote = "resolution_note"
            case evidenceVerbatim = "evidence_verbatim"
        }
        public init(threadID: String, resolutionNote: String, evidenceVerbatim: String) {
            self.threadID = threadID
            self.resolutionNote = resolutionNote
            self.evidenceVerbatim = evidenceVerbatim
        }
    }

    public struct LoopDraft: Codable, Sendable {
        public var subjectRef: String
        public var direction: String
        public var description: String
        public var dueAt: String?
        public var duePrecision: String?
        public var verbatim: String
        enum CodingKeys: String, CodingKey {
            case subjectRef = "subject_ref"
            case direction, description
            case dueAt = "due_at"
            case duePrecision = "due_precision"
            case verbatim
        }
        public init(subjectRef: String, direction: String, description: String,
                    dueAt: String? = nil, duePrecision: String? = nil, verbatim: String) {
            self.subjectRef = subjectRef
            self.direction = direction
            self.description = description
            self.dueAt = dueAt
            self.duePrecision = duePrecision
            self.verbatim = verbatim
        }
    }

    public struct ContactPointDraft: Codable, Sendable {
        public var subjectRef: String
        public var kind: String
        public var value: String
        public var verbatim: String
        enum CodingKeys: String, CodingKey {
            case subjectRef = "subject_ref"
            case kind, value, verbatim
        }
        public init(subjectRef: String, kind: String, value: String, verbatim: String) {
            self.subjectRef = subjectRef
            self.kind = kind
            self.value = value
            self.verbatim = verbatim
        }
    }

    /// §7.13: fires only on an explicit, quotable self-characterization (INV-24).
    public struct StateDeclaration: Codable, Sendable {
        public var subjectRef: String
        public var quote: String                 // verbatim substring, mechanically checked
        public var suggestedOrbit: String?
        public var suggestedIntent: String?
        public var mappingRationale: String
        enum CodingKeys: String, CodingKey {
            case subjectRef = "subject_ref"
            case quote
            case suggestedOrbit = "suggested_orbit"
            case suggestedIntent = "suggested_intent"
            case mappingRationale = "mapping_rationale"
        }
        public init(subjectRef: String, quote: String, suggestedOrbit: String? = nil,
                    suggestedIntent: String? = nil, mappingRationale: String) {
            self.subjectRef = subjectRef
            self.quote = quote
            self.suggestedOrbit = suggestedOrbit
            self.suggestedIntent = suggestedIntent
            self.mappingRationale = mappingRationale
        }
    }

    /// Decision 2: the speaker says a past belief was wrong (never_true → CORRECT)
    /// or over (no_longer_true → CLOSE). Matched against open facts at sync time.
    public struct CorrectionDraft: Codable, Sendable {
        public var subjectRef: String
        public var predicate: String
        public var objectLike: String            // matches the stored fact loosely
        public var kind: String                  // never_true | no_longer_true
        public var verbatim: String
        public var validTo: String?              // for no_longer_true
        enum CodingKeys: String, CodingKey {
            case subjectRef = "subject_ref"
            case predicate
            case objectLike = "object_like"
            case kind, verbatim
            case validTo = "valid_to"
        }
        public init(subjectRef: String, predicate: String, objectLike: String, kind: String,
                    verbatim: String, validTo: String? = nil) {
            self.subjectRef = subjectRef
            self.predicate = predicate
            self.objectLike = objectLike
            self.kind = kind
            self.verbatim = verbatim
            self.validTo = validTo
        }
    }

    /// §11: "the system should not silently guess when attribution is uncertain."
    public struct Ambiguity: Codable, Sendable {
        public var question: String
        public var candidateRefs: [String]
        /// A held fact awaiting its subject (optional — some ambiguities are
        /// pure questions, e.g. a namesake collision).
        public var assertion: AssertionDraft?
        public var kind: String                  // subject | self_collision | attendance
        enum CodingKeys: String, CodingKey {
            case question
            case candidateRefs = "candidate_refs"
            case assertion, kind
        }
        public init(question: String, candidateRefs: [String],
                    assertion: AssertionDraft? = nil, kind: String = "subject") {
            self.question = question
            self.candidateRefs = candidateRefs
            self.assertion = assertion
            self.kind = kind
        }
    }
}
