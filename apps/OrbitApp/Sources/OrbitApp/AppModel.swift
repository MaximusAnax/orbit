import Foundation
import OrbitCore
import OrbitSQLite
import OrbitStore
import OrbitWrite
import OrbitPipeline
import OrbitRecall
#if canImport(Security)
import Security
#endif

/// App-level composition root. Owns the single writer (INV-5 funnel) and hands
/// read-only state to views. All heavy work happens off the main actor.
@MainActor
final class AppModel: ObservableObject {
    let store: WriteStore
    let edits: UserEditService
    let proposals: ProposalResolutionService
    let sync: SyncEngine
    let transcription: TranscriptionService
    let recorder: AudioRecording

    @Published var selfID: String?
    @Published var pendingCapture: CaptureFlowState?
    /// Test seams: journeys await `runExtraction` directly (autoExtract=false)
    /// and inject a replay extractor — the production path everywhere else.
    nonisolated(unsafe) var extractorOverride: Extractor?
    var autoExtract = true
    @Published var setAsideCount: Int = 0     // real count, never rounded (D-9)
    @Published var todayItems: [TodayItem] = []

    struct TodayItem: Identifiable {
        let id: String
        let personID: String
        let personName: String
        let reason: String       // Principle 9: the reason travels with the reminder
    }

    enum CaptureFlowState {
        case recording
        case transcribing(audioRef: String?)
        case reviewingTranscript(TranscriptReviewViewModel)
        case extracting(eventID: String)
        case reviewingProposals(ReviewViewModel)
    }

    init(store: WriteStore, transcription: TranscriptionService,
         recorder: AudioRecording = MockRecorder()) {
        self.store = store
        self.edits = UserEditService(store)
        self.proposals = ProposalResolutionService(store)
        self.sync = SyncEngine(store)
        self.transcription = transcription
        self.recorder = recorder
        self.selfID = try? store.reader.selfPerson()?.text("id")
        refreshAmbient()
    }

    static func production() throws -> AppModel {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        // Data protection: complete-until-first-auth; DB encrypted at rest by iOS
        // file protection (DATA-MODEL §5). PRIV-2: the only content egress is the
        // extraction endpoint inside RemoteExtractor.
        let store = try WriteStore.at(path: dir.appendingPathComponent("orbit.sqlite").path)
        #if canImport(AVFoundation) && os(iOS)
        let recorder: AudioRecording = DeviceRecorder()
        #else
        let recorder: AudioRecording = MockRecorder()
        #endif
        return AppModel(store: store, transcription: WhisperTranscriber(models: ModelManager()),
                        recorder: recorder)
    }

    /// UI-test boot (J-1..J-5, J-11, J-12): in-memory store, canned transcript,
    /// replayed extraction payload — the production code path everywhere else.
    static func uiTest(env: [String: String]) -> AppModel {
        let store = try! WriteStore.inMemory()
        let model = AppModel(
            store: store,
            transcription: MockTranscriber(canned: env["ORBIT_UITEST_TRANSCRIPT"] ?? "",
                                           full: env["ORBIT_UITEST_TINY_MODEL"] == nil),
            recorder: MockRecorder())
        model.ensureSelf(named: env["ORBIT_UITEST_SELF"] ?? "Abdoul")
        return model
    }

    /// Minimal onboarding: the quiet self profile (§7.12) — created once, invisible.
    func ensureSelf(named name: String) {
        guard selfID == nil else { return }
        selfID = try? edits.createPerson(displayName: name, isSelf: true)
    }

    // MARK: ambient state (home)

    func refreshAmbient() {
        // set-asides: deferred proposals across all events — a footer line, never a badge (D-2)
        setAsideCount = Int((try? store.db.scalar(
            "SELECT COUNT(*) FROM proposal WHERE state='deferred'").intValue) ?? 0)
        todayItems = computeToday()
    }

    /// "Today": at most two context items, only when genuinely timely (DESIGN §12).
    /// Sources: a life event inside its window; a thread just past its expected
    /// resolution. Hardship threads never appear (INV-20). No frequency nagging.
    func computeToday() -> [TodayItem] {
        let now = store.clock.now()
        let month = String(now.prefix(7))
        var items: [TodayItem] = []
        if let rows = try? store.db.query(
            """
            SELECT cs.assertion_id, cs.subject_id, p.display_name, cs.verbatim
            FROM rm_current_state cs
            JOIN person p ON p.id = cs.subject_id
            WHERE cs.predicate = 'life_event' AND cs.valid_from LIKE ? || '%'
              AND p.is_self = 0
            LIMIT 2
            """, [.text(month)]) {
            for r in rows {
                items.append(TodayItem(
                    id: r.text("assertion_id") ?? UUID().uuidString,
                    personID: r.text("subject_id") ?? "",
                    personName: r.text("display_name") ?? "",
                    reason: "\u{201C}\(r.text("verbatim") ?? "")\u{201D} — that's this month"))
            }
        }
        if items.count < 2, let rows = try? store.db.query(
            """
            SELECT t.id, t.person_id, p.display_name, t.title
            FROM thread t JOIN person p ON p.id = t.person_id
            WHERE t.state='open' AND t.prompt_state='active'
              AND t.archetype NOT IN ('condition_hardship','aspiration')   -- INV-20
              AND t.expected_resolution_at IS NOT NULL AND t.expected_resolution_at <= ?
            LIMIT ?
            """, [.text(now), .integer(Int64(2 - items.count))]) {
            for r in rows {
                items.append(TodayItem(
                    id: r.text("id") ?? UUID().uuidString,
                    personID: r.text("person_id") ?? "",
                    personName: r.text("display_name") ?? "",
                    reason: "\u{201C}\(r.text("title") ?? "")\u{201D} should have an answer by now"))
            }
        }
        return Array(items.prefix(2))
    }

    // MARK: capture flow

    /// Typed micro-note: the typed text IS the transcript (§7.11), everything
    /// downstream identical.
    func captureTypedNote(text: String, about personID: String) throws {
        let event = try edits.captureEvent(.init(
            kind: .note, occurredAt: store.clock.now(), transcript: text,
            participants: [(personID, .about, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: true)   // no audio to gate
        startExtraction(eventID: event)
    }

    /// Typed note with no person picked up front — extraction identifies who
    /// it's about and the ABOUT attendance arrives via the sync engine (§7.11).
    func captureTypedNote(text: String) throws {
        let event = try edits.captureEvent(.init(
            kind: .note, occurredAt: store.clock.now(), transcript: text, participants: []))
        try edits.confirmEvent(event, fullModelTranscribed: true)
        startExtraction(eventID: event)
    }

    func beginRecording() {
        do {
            try recorder.begin()
            pendingCapture = .recording
        } catch {
            pendingCapture = nil   // mic unavailable: the typed note is right there (P3)
        }
    }

    func endRecording(kind: EventKind = .encounter) async {
        guard let audioRef = try? recorder.end() else {
            pendingCapture = nil
            return
        }
        await finishRecording(audioRef: audioRef, participants: [], kind: kind)
    }

    func finishRecording(audioRef: String, participants: [(String, Attendance, String?)],
                         kind: EventKind) async {
        pendingCapture = .transcribing(audioRef: audioRef)
        let primer = knownNamesPrimer()
        do {
            let result = try await transcription.transcribe(audioAt: audioRef, primedWith: primer)
            let event = try edits.captureEvent(.init(
                kind: kind, occurredAt: store.clock.now(),
                transcript: result.text, audioRef: audioRef, participants: participants))
            let vm = TranscriptReviewViewModel(
                eventID: event, text: result.text, usedFullModel: result.usedFullModel,
                matcher: NameMatcher(knownNames: primer), app: self)
            pendingCapture = .reviewingTranscript(vm)
        } catch {
            pendingCapture = nil
        }
    }

    func transcriptConfirmed(eventID: String, finalText: String, usedFullModel: Bool) {
        try? edits.editTranscript(event: eventID, transcript: finalText)
        // §7.5 gate: audio deleted ONLY when the full model transcribed.
        try? edits.confirmEvent(eventID, fullModelTranscribed: usedFullModel)
        startExtraction(eventID: eventID)
    }

    func startExtraction(eventID: String) {
        pendingCapture = .extracting(eventID: eventID)
        guard autoExtract else { return }
        Task { await runExtraction(eventID: eventID) }
    }

    func runExtraction(eventID: String) async {
        do {
            let transcript = try store.reader.effectiveEvent(eventID)?["transcript"]?.stringValue ?? ""
            let context = extractionContext(eventID: eventID)
            let extractor = makeExtractor()
            let result = try await extractor.extract(transcript: transcript, context: context)
            let outcome = try sync.sync(event: eventID, extractionVersion: 1, result: result)
            pendingCapture = .reviewingProposals(ReviewViewModel(syncRunID: outcome.syncRunID, app: self))
        } catch {
            // Sync-later: the event stays confirmed+unsynced, resumable from the
            // home footer (J-11). No nagging (P10).
            pendingCapture = nil
        }
    }

    /// Resume an unsynced event later (J-11) — proposals identical to immediate sync.
    func syncLater(eventID: String) {
        startExtraction(eventID: eventID)
    }

    /// The ceiling model downloads during onboarding dead time (§6); quiet,
    /// resumed on next launch if it doesn't finish.
    func warmModels() {
        guard let whisper = transcription as? WhisperTranscriber else { return }
        let models = whisper.models
        Task.detached(priority: .utility) {
            await models.downloadCeilingIfNeeded()
        }
    }

    // MARK: recall (Desk & Deck)

    func assembleBrief(personID: String) throws -> Brief {
        try BriefAssembler(reader: store.reader).assemble(personID: personID,
                                                          now: store.clock.now())
    }

    nonisolated func makeExtractor() -> Extractor {
        if let override = extractorOverride { return override }
        // UI tests replay a recorded payload through the production sync path.
        if let json = ProcessInfo.processInfo.environment["ORBIT_UITEST_PAYLOAD"] {
            return StaticPayloadExtractor(json: json)
        }
        // Keys live in the keychain, entered once in settings. Provider is
        // selected by which key exists (Anthropic wins if both — the ratified
        // default; OpenAI is the configured alternative, Abdoul 2026-07-29).
        // Data-retention posture per BUILD.md §1.3 applies to whichever runs.
        // Nothing outside OrbitPipeline knows which provider ran (§7.9).
        if let extractor = ExtractionProvider.fromEnvironment(
            anthropicKey: KeychainLite.read("anthropic-api-key"),
            openAIKey: KeychainLite.read("openai-api-key")) {
            return extractor
        }
        return UnavailableExtractor()
    }

    func knownNamesPrimer() -> [String] {
        ((try? store.db.query("SELECT display_name FROM person WHERE status != 'merged'")) ?? [])
            .compactMap { $0.text("display_name") }
    }

    func extractionContext(eventID: String) -> ExtractionContext {
        let people = ((try? store.db.query(
            "SELECT id, display_name FROM person WHERE status != 'merged' AND is_self = 0")) ?? [])
            .compactMap { row -> (String, String)? in
                guard let id = row.text("id"), let name = row.text("display_name") else { return nil }
                return (id, name)
            }
        let entities = ((try? store.db.query(
            """
            SELECT e.id, e.canonical_name, GROUP_CONCAT(a.alias, '||') AS aliases
            FROM entity e LEFT JOIN entity_alias a ON a.entity_id = e.id
            WHERE e.merged_into IS NULL GROUP BY e.id
            """)) ?? [])
            .compactMap { row -> (String, String, [String])? in
                guard let id = row.text("id"), let name = row.text("canonical_name") else { return nil }
                return (id, name, (row.text("aliases") ?? "").split(separator: "||").map(String.init))
            }
        // era anchors (§7.12): the self row's education intervals
        let anchors = (selfID.flatMap { try? store.reader.currentState(of: $0) } ?? [])
            .filter { $0.text("predicate") == "education" }
            .compactMap { row -> String? in
                guard let v = row.text("verbatim") else { return nil }
                let from = row.text("valid_from") ?? "?"
                return "\(v) (from \(from))"
            }
        return ExtractionContext(
            eventKind: (try? store.reader.effectiveEvent(eventID)?["kind"]?.stringValue) ?? "note",
            capturedAt: store.clock.now(),
            knownPeople: people, knownEntities: entities,
            selfName: (try? store.reader.selfPerson()?.text("display_name")) ?? "",
            selfAnchors: anchors)
    }
}

/// Placeholder extractor when no key is configured: capture still works; the
/// event waits, honestly, for sync-later (P3 — capture must never hard-fail).
struct UnavailableExtractor: Extractor {
    func extract(transcript: String, context: ExtractionContext) async throws -> ExtractionResult {
        throw ExtractorError.transport("no extraction key configured — memo saved, sync later")
    }
}

/// UI-test extractor: decodes a fixture payload passed via launch environment,
/// so journeys exercise the real SyncEngine → proposal → review path.
struct StaticPayloadExtractor: Extractor {
    var json: String
    func extract(transcript: String, context: ExtractionContext) async throws -> ExtractionResult {
        let payload = try JSONDecoder().decode(ExtractionPayload.self, from: Data(json.utf8))
        return ExtractionResult(payload: payload, modelID: "uitest-replay", promptVersion: "v1")
    }
}

/// API keys at rest: Security.framework where a keychain exists (device-only
/// accessibility — the key never rides iCloud Keychain), env-var fallback
/// where none does (CI, Linux harness). The keychain item is the durable
/// store; env vars exist so `orbit-evals measure --live` works headless.
enum KeychainLite {
    nonisolated(unsafe) static var overrideForTesting: [String: String] = [:]
    static let service = "dev.abdoul.orbit"
    static let envNames = [
        "anthropic-api-key": "ANTHROPIC_API_KEY",
        "openai-api-key": "OPENAI_API_KEY",
    ]

    static func read(_ key: String) -> String? {
        if let v = overrideForTesting[key] { return v.isEmpty ? nil : v }
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let value = String(data: data, encoding: .utf8), !value.isEmpty {
            return value
        }
        #endif
        guard let env = envNames[key] else { return nil }
        return ProcessInfo.processInfo.environment[env]
    }

    /// Empty value removes the item.
    @discardableResult
    static func write(_ key: String, value: String) -> Bool {
        #if canImport(Security)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        #else
        overrideForTesting[key] = value
        return true
        #endif
    }
}
