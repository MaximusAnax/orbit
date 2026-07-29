import Foundation

// Proposal payloads — the JSON stored in proposal.payload / edited_payload.
// Shared vocabulary between the pipeline (which writes proposals) and OrbitWrite
// (which applies accepted ones). Codable with snake_case keys to match fixtures.

/// A person mentioned by a payload: either an existing row or a run-local ref
/// that a CREATE_PERSON acceptance will materialize (resolved via sync_person_ref).
public enum PersonRef: Codable, Equatable, Sendable {
    case id(String)
    case ref(String)

    enum CodingKeys: String, CodingKey { case personID = "person_id", personRef = "person_ref" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .personID) {
            self = .id(id)
        } else {
            self = .ref(try c.decode(String.self, forKey: .personRef))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .id(let id): try c.encode(id, forKey: .personID)
        case .ref(let r): try c.encode(r, forKey: .personRef)
        }
    }
}

public enum EntityRef: Codable, Equatable, Sendable {
    case id(String)
    case ref(String)

    enum CodingKeys: String, CodingKey { case entityID = "entity_id", entityRef = "entity_ref" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .entityID) {
            self = .id(id)
        } else {
            self = .ref(try c.decode(String.self, forKey: .entityRef))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .id(let id): try c.encode(id, forKey: .entityID)
        case .ref(let r): try c.encode(r, forKey: .entityRef)
        }
    }
}

public struct AssertPayload: Codable, Sendable {
    public var subject: PersonRef
    public var predicate: String
    public var objectEntity: EntityRef?
    public var objectValue: String?
    public var verbatim: String
    public var validFrom: String?
    public var validTo: String?
    public var datePrecision: String
    public var sourceKind: String
    public var attributedTo: PersonRef?
    public var confidence: Double?
    public var threadRef: String?

    enum CodingKeys: String, CodingKey {
        case subject, predicate
        case objectEntity = "object_entity"
        case objectValue = "object_value"
        case verbatim
        case validFrom = "valid_from"
        case validTo = "valid_to"
        case datePrecision = "date_precision"
        case sourceKind = "source_kind"
        case attributedTo = "attributed_to"
        case confidence
        case threadRef = "thread_ref"
    }

    public init(subject: PersonRef, predicate: String, objectEntity: EntityRef? = nil,
                objectValue: String? = nil, verbatim: String, validFrom: String? = nil,
                validTo: String? = nil, datePrecision: String = "fuzzy",
                sourceKind: String = "firsthand", attributedTo: PersonRef? = nil,
                confidence: Double? = nil, threadRef: String? = nil) {
        self.subject = subject
        self.predicate = predicate
        self.objectEntity = objectEntity
        self.objectValue = objectValue
        self.verbatim = verbatim
        self.validFrom = validFrom
        self.validTo = validTo
        self.datePrecision = datePrecision
        self.sourceKind = sourceKind
        self.attributedTo = attributedTo
        self.confidence = confidence
        self.threadRef = threadRef
    }
}

public struct ClosePayload: Codable, Sendable {
    public var validTo: String
    public var verbatim: String?   // what was said that closes it ("she left Google")
    enum CodingKeys: String, CodingKey { case validTo = "valid_to", verbatim }
    public init(validTo: String, verbatim: String? = nil) {
        self.validTo = validTo
        self.verbatim = verbatim
    }
}

public struct CorrectPayload: Codable, Sendable {
    public var reason: String
    public init(reason: String) { self.reason = reason }
}

public struct CreatePersonPayload: Codable, Sendable {
    public var ref: String
    public var displayName: String
    public var status: String       // provisional | active | known_of
    enum CodingKeys: String, CodingKey { case ref, displayName = "display_name", status }
    public init(ref: String, displayName: String, status: String = "active") {
        self.ref = ref
        self.displayName = displayName
        self.status = status
    }
}

public struct LinkEntityPayload: Codable, Sendable {
    public var ref: String
    /// Existing entity to link to — nil means create a new one.
    public var existingEntityID: String?
    public var kind: String?
    public var canonicalName: String?
    public var partOf: EntityRef?
    public var aliases: [String]
    enum CodingKeys: String, CodingKey {
        case ref
        case existingEntityID = "existing_entity_id"
        case kind
        case canonicalName = "canonical_name"
        case partOf = "part_of"
        case aliases
    }
    public init(ref: String, existingEntityID: String? = nil, kind: String? = nil,
                canonicalName: String? = nil, partOf: EntityRef? = nil, aliases: [String] = []) {
        self.ref = ref
        self.existingEntityID = existingEntityID
        self.kind = kind
        self.canonicalName = canonicalName
        self.partOf = partOf
        self.aliases = aliases
    }
}

public struct OpenLoopPayload: Codable, Sendable {
    public var person: PersonRef
    public var direction: String
    public var description: String
    public var dueAt: String?
    public var duePrecision: String?
    enum CodingKeys: String, CodingKey {
        case person, direction, description
        case dueAt = "due_at"
        case duePrecision = "due_precision"
    }
    public init(person: PersonRef, direction: String, description: String,
                dueAt: String? = nil, duePrecision: String? = nil) {
        self.person = person
        self.direction = direction
        self.description = description
        self.dueAt = dueAt
        self.duePrecision = duePrecision
    }
}

public struct OpenThreadPayload: Codable, Sendable {
    public var ref: String              // run-local; ASSERT payloads may join via thread_ref
    public var person: PersonRef
    public var title: String
    public var archetype: String
    public var expectedResolutionAt: String?
    public var expectedResolutionPrecision: String?
    enum CodingKeys: String, CodingKey {
        case ref, person, title, archetype
        case expectedResolutionAt = "expected_resolution_at"
        case expectedResolutionPrecision = "expected_resolution_precision"
    }
    public init(ref: String, person: PersonRef, title: String, archetype: String,
                expectedResolutionAt: String? = nil, expectedResolutionPrecision: String? = nil) {
        self.ref = ref
        self.person = person
        self.title = title
        self.archetype = archetype
        self.expectedResolutionAt = expectedResolutionAt
        self.expectedResolutionPrecision = expectedResolutionPrecision
    }
}

public struct CloseThreadPayload: Codable, Sendable {
    public var threadID: String
    public var resolutionNote: String
    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case resolutionNote = "resolution_note"
    }
    public init(threadID: String, resolutionNote: String) {
        self.threadID = threadID
        self.resolutionNote = resolutionNote
    }
}

/// §7.13: the narrative MUST be a verbatim substring of the source transcript —
/// checked mechanically at proposal creation AND at application (INV-24).
public struct ProposeStatePayload: Codable, Sendable {
    public var person: PersonRef
    public var narrativeQuote: String
    public var suggestedOrbit: String?
    public var suggestedIntent: String?
    public var mappingRationale: String
    enum CodingKeys: String, CodingKey {
        case person
        case narrativeQuote = "narrative_quote"
        case suggestedOrbit = "suggested_orbit"
        case suggestedIntent = "suggested_intent"
        case mappingRationale = "mapping_rationale"
    }
    public init(person: PersonRef, narrativeQuote: String, suggestedOrbit: String? = nil,
                suggestedIntent: String? = nil, mappingRationale: String) {
        self.person = person
        self.narrativeQuote = narrativeQuote
        self.suggestedOrbit = suggestedOrbit
        self.suggestedIntent = suggestedIntent
        self.mappingRationale = mappingRationale
    }
}

/// "Was this James?" — an assertion whose subject is genuinely unknown (Decision 5).
public struct DisambiguatePayload: Codable, Sendable {
    public var question: String
    public var candidates: [PersonRef]
    public var assertion: AssertPayload    // subject field ignored until resolution
    public init(question: String, candidates: [PersonRef], assertion: AssertPayload) {
        self.question = question
        self.candidates = candidates
        self.assertion = assertion
    }
}

public struct MergePayload: Codable, Sendable {
    public var loserID: String
    public var winnerID: String
    enum CodingKeys: String, CodingKey {
        case loserID = "loser_id"
        case winnerID = "winner_id"
    }
    public init(loserID: String, winnerID: String) {
        self.loserID = loserID
        self.winnerID = winnerID
    }
}

/// §7.11 reconstructed episode from a portrait.
public struct CreateEventPayload: Codable, Sendable {
    public var occurredAt: String
    public var datePrecision: String
    public var kind: String
    public var title: String?
    public var narrative: String            // the verbatim slice of the portrait
    public var participants: [Participant]
    public var locationEntity: EntityRef?

    public struct Participant: Codable, Sendable {
        public var person: PersonRef
        public var attendance: String
        public var role: String?
        public init(person: PersonRef, attendance: String = "confirmed", role: String? = nil) {
            self.person = person
            self.attendance = attendance
            self.role = role
        }
    }

    enum CodingKeys: String, CodingKey {
        case occurredAt = "occurred_at"
        case datePrecision = "date_precision"
        case kind, title, narrative, participants
        case locationEntity = "location_entity"
    }
    public init(occurredAt: String, datePrecision: String, kind: String, title: String?,
                narrative: String, participants: [Participant], locationEntity: EntityRef? = nil) {
        self.occurredAt = occurredAt
        self.datePrecision = datePrecision
        self.kind = kind
        self.title = title
        self.narrative = narrative
        self.participants = participants
        self.locationEntity = locationEntity
    }
}

public struct ContactPointPayload: Codable, Sendable {
    public var person: PersonRef
    public var kind: String
    public var value: String
    public var label: String?
    public var source: String    // 'voice' renders unverified until first used (§7.8)
    public init(person: PersonRef, kind: String, value: String, label: String? = nil, source: String = "voice") {
        self.person = person
        self.kind = kind
        self.value = value
        self.label = label
        self.source = source
    }
}

public enum PayloadCoding {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]   // deterministic payload bytes
        return e
    }()
    public static let decoder = JSONDecoder()

    public static func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try encoder.encode(value), encoding: .utf8)!
    }
    public static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }
}
