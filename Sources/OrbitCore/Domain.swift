import Foundation

// Domain vocabulary — string-backed to match the schema CHECK constraints exactly.
// The database is the enforcement layer; these enums keep Swift call sites honest.

public enum PersonStatus: String, Sendable, CaseIterable {
    case provisional, active, knownOf = "known_of", merged
}

public enum EventKind: String, Sendable, CaseIterable {
    case dinner, coffee, call, text, conference, party, meeting, introduction, encounter, note, portrait
}

public enum EventLifecycle: String, Sendable { case captured, confirmed, discarded }

public enum Attendance: String, Sendable { case confirmed, probable, about }

public enum Predicate: String, Sendable, CaseIterable {
    case employment, education, location, interest, skill, goal, concern
    case relation, lifeEvent = "life_event", preference, trait
}

public enum SourceKind: String, Sendable { case firsthand, secondhand }

public enum DatePrecision: String, Sendable { case exact, month, year, fuzzy }

public enum ProposalOp: String, Sendable, CaseIterable {
    case assert = "ASSERT"
    case close = "CLOSE"
    case correct = "CORRECT"
    case merge = "MERGE"
    case link = "LINK"
    case createPerson = "CREATE_PERSON"
    case createEvent = "CREATE_EVENT"
    case openLoop = "OPEN_LOOP"
    case proposeState = "PROPOSE_STATE"
    case disambiguate = "DISAMBIGUATE"
    case openThread = "OPEN_THREAD"
    case closeThread = "CLOSE_THREAD"
    case contactPoint = "CONTACT_POINT"
}

public enum ProposalState: String, Sendable { case pending, accepted, rejected, deferred, superseded }

public enum ReviewAction: String, Sendable { case accepted, rejected, edited, deferred }

public enum RejectionReason: String, Sendable {
    case notTrue = "not_true", wrongPerson = "wrong_person", notWorthKeeping = "not_worth_keeping"
}

public enum Orbit: String, Sendable, CaseIterable { case inner, close, active, extended, outer }

public enum MaintenanceMode: String, Sendable { case resilient, deliberate, dormantByChoice = "dormant_by_choice", unset }

public enum ThreadArchetype: String, Sendable, CaseIterable {
    case eventPending = "event_pending"
    case decision
    case project
    case conditionProcess = "condition_process"
    case conditionHardship = "condition_hardship"
    case aspiration

    /// §9.3 decay defaults: conversations-without-mention before prompt_state
    /// decays to context_only. nil = never decays.
    public var decayConversations: Int? {
        switch self {
        case .eventPending: return 1
        case .decision: return 3          // "2–3" — ties break slow (§9.3)
        case .project: return 4           // "3–4"
        case .conditionProcess: return 2
        case .conditionHardship: return nil   // never decays, never prompts (INV-20)
        case .aspiration: return nil          // context from birth, prompts never
        }
    }

    /// May this archetype ever generate a proactive suggestion? (INV-20 / §9.3)
    public var mayPrompt: Bool {
        switch self {
        case .conditionHardship, .aspiration: return false
        default: return true
        }
    }
}

public enum ThreadState: String, Sendable { case open, resolved }
public enum ThreadPromptState: String, Sendable { case active, contextOnly = "context_only" }

public enum LoopDirection: String, Sendable { case abdoulOwes = "abdoul_owes", personOwes = "person_owes" }
public enum LoopState: String, Sendable { case open, resolved, dropped, expired }

public enum EntityKind: String, Sendable, CaseIterable {
    case organization, school, place, topic, skill, eventSeries = "event_series"
}

public enum ContactPointKind: String, Sendable { case phone, email, instagram, linkedin, x, website, other }
public enum ContactPointSource: String, Sendable { case linkedContact = "linked_contact", manual, voice, `import` }

// MARK: - Identifiers & time

public enum OrbitID {
    public static func make() -> String { UUID().uuidString.lowercased() }
}

/// Injectable clock so tests and replays are deterministic.
public protocol OrbitClock: Sendable {
    func now() -> String  // ISO-8601 UTC
}

public struct SystemClock: OrbitClock {
    public init() {}
    public func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}

public struct FixedClock: OrbitClock {
    public var value: String
    public init(_ value: String) { self.value = value }
    public func now() -> String { value }
}
