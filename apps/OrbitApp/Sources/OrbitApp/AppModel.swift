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
    /// Memos that need him to come back: captured-but-unreviewed events and
    /// confirmed-but-unsynced ones. The home footer resumes them (J-11);
    /// nothing nags (P10).
    @Published var waitingMemos: [WaitingMemo] = []

    /// Why the mic didn't start, when it didn't. `denied` is the one the user
    /// can act on; the rest carry their reason for the log rather than
    /// disappearing into a false "unavailable".
    @Published var micFailure: MicFailure?
    enum MicFailure: Equatable { case denied, unavailable(String) }

    /// Why a memo couldn't be turned into text. Shown as one plain line — a
    /// tap that silently does nothing is worse than a tap that explains itself.
    @Published var captureNotice: String?

    /// He collapsed the working screen. The work itself keeps running — this
    /// only decides where its result lands: the waiting footer, rather than on
    /// top of whatever he moved on to (P10 — nothing seizes the screen).
    @Published var workCollapsed = false

    /// Transcription and extraction are the two steps slow enough to look like
    /// nothing is happening. Everything else is instant.
    var isWorking: Bool {
        switch pendingCapture {
        case .transcribing, .extracting: return true
        default: return false
        }
    }

    var workingLine: String {
        if case .extracting = pendingCapture { return Copy.workingExtracting }
        return Copy.workingTranscribing
    }

    /// Step out of the way without stopping anything.
    func collapseWork() {
        guard isWorking else { return }
        workCollapsed = true
        pendingCapture = nil
    }

    /// Hand a finished step to the screen — unless he collapsed the working
    /// view, in which case it waits in the footer instead of interrupting him.
    private func present(_ state: CaptureFlowState) {
        // Backstop for every path, not just extraction: a review with nothing in
        // it is never the right screen, so it silently becomes "no screen".
        if case .reviewingProposals(let vm) = state, vm.visibleGroups.isEmpty {
            workCollapsed = false
            pendingCapture = nil
            refreshAmbient()
            return
        }
        if workCollapsed {
            workCollapsed = false
            pendingCapture = nil
            refreshAmbient()
        } else {
            pendingCapture = state
        }
    }

    struct WaitingMemo: Identifiable {
        /// Equatable is explicit because `needsProposalReview` carries a value:
        /// Swift synthesises `==` for free only while an enum has no associated
        /// values, so adding one silently withdrew the conformance and broke
        /// every test comparing a stage (FIELD-NOTES FN-25).
        enum Stage: Equatable { case needsTranscription, needsTranscriptReview, needsSync,
                                needsProposalReview(syncRunID: String) }
        let id: String          // event id
        let stage: Stage
        /// Before a memo has words, the day it was captured is the only thing
        /// that tells one apart from another in the list.
        var capturedAt: String = ""
        /// The write layer only discards `captured` events. A confirmed memo
        /// waiting to sync has real content behind it, and offering an exit
        /// that throws is worse than offering none.
        var canDiscard: Bool {
            if case .needsTranscription = stage { return true }
            if case .needsTranscriptReview = stage { return true }
            return false
        }
    }

    /// The home kicker's date ("Saturday, July 25"). Read through the store's
    /// clock rather than `Date()` so a fixed-clock test sees a fixed screen.
    var todayDateLine: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let date = iso.date(from: store.clock.now())
            ?? ISO8601DateFormatter().date(from: store.clock.now())
            ?? Date()
        let out = DateFormatter()
        out.dateFormat = "EEEE, MMMM d"
        return out.string(from: date)
    }

    struct TodayItem: Identifiable {
        let id: String
        let personID: String
        let personName: String
        let reason: String       // Principle 9: the reason travels with the reminder
        /// The mockup's second line: where this came from, and the door it opens.
        var sourceLine: String { Copy.openBrief(personName) }
        /// The card's portrait initial (mockup `.pav`).
        var initial: String { String(personName.prefix(1)).uppercased() }
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
        // extraction endpoint inside OpenAIExtractor.
        let store = try WriteStore.at(path: dir.appendingPathComponent("orbit.sqlite").path)
        #if canImport(AVFoundation) && os(iOS)
        let recorder: AudioRecording = DeviceRecorder()
        #else
        let recorder: AudioRecording = MockRecorder()
        #endif
        // Quality first, but never nothing: whisper when its model is on the
        // phone, Apple's on-device recognizer as the floor so capture works
        // from the first launch (both stay on-device — PRIV-1).
        var stages: [TranscriptionService] = [WhisperTranscriber(models: ModelManager())]
        #if canImport(Speech) && os(iOS)
        stages.append(AppleSpeechTranscriber())
        #endif
        return AppModel(store: store, transcription: CascadingTranscriber(stages),
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

    // MARK: correcting what is already saved (FIELD-NOTES FN-13 / FN-15)

    /// Rename a saved person. Everything goes through the write funnel (INV-5).
    func renamePerson(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? edits.renamePerson(id, displayName: trimmed)
        refreshAmbient()
    }

    /// Rename a saved entity — the old name survives as an alias, so the way he
    /// said it before still resolves (§7.10 guarantee 3).
    func renameEntity(_ id: String, to name: String) {
        try? edits.renameEntity(id, canonicalName: name)
    }

    /// Correct what a saved fact says, without touching what he said. The
    /// verbatim is the record (P5) and stays; the amendment posts a correction
    /// over `object_value`, and INV-1 keeps the original readable in the ledger.
    func amendFact(_ assertionID: String, objectValue: String) {
        let trimmed = objectValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? edits.amendAssertion(assertionID, field: "object_value",
                                  newValue: trimmed, reason: "corrected on the desk")
    }

    /// What the transcription ceiling is doing, in words rather than by
    /// inference (FIELD-NOTES FN-5). Until this existed the only signal was a
    /// notice that needs three consecutive failures before it says anything, so
    /// "is the model here, and what is waiting on it" had no answer.
    /// Recordings the model is actually holding. `upgradeRetainedAudio` only
    /// re-hears `confirmed` events, so a memo still in transcript review is
    /// waiting on Abdoul, not on the download — counting it here would report
    /// the same memo twice under two incompatible explanations, once in this
    /// line and once in the "N memos waiting" footer, and only one would be
    /// true. This is the set the re-listen pass will act on, nothing wider.
    private var awaitingReListen: Int {
        Int((try? store.db.scalar(
            "SELECT COUNT(*) FROM event "
            + "WHERE lifecycle='confirmed' AND raw_audio_ref IS NOT NULL").intValue) ?? 0)
    }

    var modelStatusLine: String {
        let models = whisperTranscriber?.models ?? ModelManager()
        // Counted once, before either branch: the model arriving does not empty
        // the backlog. Floor-transcribed memos keep their audio until
        // `upgradeRetainedAudio` re-hears them, so reporting "nothing waiting"
        // on `ceilingURL != nil` alone re-introduced exactly the inference this
        // line exists to replace.
        let retained = awaitingReListen
        if models.ceilingURL != nil {
            return retained > 0 ? Copy.modelPresentCatchingUp(retained) : Copy.modelPresent
        }
        guard retained > 0 else { return Copy.modelAbsentNothingKept }
        return Copy.modelAbsent(retained, failures: models.consecutiveDownloadFailures)
    }

    /// Add a handle by hand. ORBIT.md §Contact Points lists these across
    /// platforms, and they are the one kind of data voice capture is worst at:
    /// "@ j dash smith underscore 92" survives no transcriber, and unlike a
    /// remembered fact a typo makes it useless rather than merely imprecise.
    /// `source: .manual` distinguishes it from voice-derived handles, which
    /// carry the §7.8 unverified-until-used state — typed by hand is not a guess.
    func addContact(person: String, kind: ContactPointKind, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? edits.addContactPoint(person: person, kind: kind, value: trimmed,
                                       source: .manual)
    }

    /// Withdraw someone from every surface, keeping everything they anchor.
    func retire(person id: String) {
        try? edits.retirePerson(id)
        refreshAmbient()
    }

    struct RosterEntry: Identifiable {
        let id: String
        let name: String
        let isKnownOf: Bool
    }

    /// Everyone saved, A–Z. Search answers "where is this person"; nothing
    /// answered "who do I have", so every Desk was unreachable unless you
    /// already knew the name to type.
    ///
    /// Alphabetical on purpose: P6 forbids people lists *sorted by anything*
    /// that implies ranking — recency, frequency, closeness. A–Z is an index,
    /// carries no judgement, and is the one order that says nothing about
    /// anybody. Merged rows are excluded (they are pointers, not people) and so
    /// is the self row (§7.12 keeps it invisible).
    func roster() -> [RosterEntry] {
        ((try? store.db.query(
            """
            SELECT id, display_name, status FROM person
            WHERE is_self = 0 AND status != 'merged'
              AND NOT EXISTS (SELECT 1 FROM person_retirement r WHERE r.person_id = person.id)
            ORDER BY display_name COLLATE NOCASE
            """)) ?? []).compactMap { row in
                guard let id = row.text("id"), let name = row.text("display_name") else { return nil }
                return RosterEntry(id: id, name: name,
                                   isKnownOf: row.text("status") == "known_of")
            }
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
        waitingMemos = computeWaiting()
    }

    func computeWaiting() -> [WaitingMemo] {
        var out: [WaitingMemo] = []
        // captured, never confirmed: audio-only (transcription pending) or
        // transcript awaiting review
        if let rows = try? store.db.query(
            "SELECT id, transcript, captured_at FROM event WHERE lifecycle='captured' ORDER BY captured_at") {
            for r in rows {
                guard let id = r.text("id") else { continue }
                out.append(WaitingMemo(
                    id: id,
                    stage: r.text("transcript") == nil ? .needsTranscription : .needsTranscriptReview,
                    capturedAt: r.text("captured_at") ?? ""))
            }
        }
        // confirmed but never synced (J-11)
        if let rows = try? store.db.query(
            "SELECT e.id, e.confirmed_at FROM event e WHERE e.lifecycle='confirmed' " +
            "AND NOT EXISTS (SELECT 1 FROM sync_run s WHERE s.event_id = e.id) " +
            "ORDER BY e.confirmed_at") {
            for r in rows {
                if let id = r.text("id") {
                    out.append(WaitingMemo(id: id, stage: .needsSync,
                                           capturedAt: r.text("confirmed_at") ?? ""))
                }
            }
        }
        // extracted, proposals never answered: `setAsideCount` only counts
        // 'deferred', so a run left in 'pending' (app killed mid-review, or the
        // working screen collapsed while extraction finished) had no way back.
        if let rows = try? store.db.query(
            """
            SELECT s.event_id AS id, s.id AS run, e.confirmed_at AS at
            FROM sync_run s JOIN event e ON e.id = s.event_id
            WHERE EXISTS (SELECT 1 FROM proposal p
                          WHERE p.sync_run_id = s.id AND p.state='pending')
            ORDER BY e.confirmed_at, s.created_at
            """) {
            // One row per sync RUN, and re-extraction is a supported thing
            // (`openSyncRun` always creates a new one, `extractionVersion`
            // exists, INV-7 exists to suppress the repeat claims) — so an event
            // extracted twice appeared twice here, as two memos with the same
            // WaitingMemo.id. Identical rows in the list, and duplicate ids in a
            // ForEach on top of that. One memo is one entry; the oldest
            // unanswered run is the one to open.
            var seen = Set<String>()
            for r in rows {
                guard let id = r.text("id"), let run = r.text("run"),
                      seen.insert(id).inserted else { continue }
                out.append(WaitingMemo(id: id, stage: .needsProposalReview(syncRunID: run),
                                       capturedAt: r.text("at") ?? ""))
            }
        }
        return out
    }

    /// Resume whatever a waiting memo needs next — the J-11 door.
    func resume(_ memo: WaitingMemo) {
        switch memo.stage {
        case .needsTranscription:
            Task { await transcribeExisting(eventID: memo.id) }
        case .needsTranscriptReview:
            let transcript = (try? store.db.scalar(
                "SELECT transcript FROM event WHERE id=?", [.text(memo.id)]).stringValue)
                .flatMap { $0 } ?? ""
            let primer = knownNamesPrimer()
            pendingCapture = .reviewingTranscript(TranscriptReviewViewModel(
                eventID: memo.id, text: transcript,
                usedFullModel: false,   // conservative: audio survives until a full-model pass
                matcher: NameMatcher(knownNames: primer), app: self))
        case .needsSync:
            syncLater(eventID: memo.id)
        case .needsProposalReview(let runID):
            pendingCapture = .reviewingProposals(ReviewViewModel(syncRunID: runID, app: self))
        }
    }

    /// Reopen the set-asides: the earliest sync run still holding deferred
    /// proposals (the footer tap-through — D-2 honest counterpart).
    func reopenSetAsides() {
        guard let run = try? store.db.scalar(
            "SELECT sync_run_id FROM proposal WHERE state='deferred' ORDER BY rowid LIMIT 1"
        ).stringValue else { return }
        pendingCapture = .reviewingProposals(ReviewViewModel(syncRunID: run, app: self))
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
              AND p.is_self = 0 AND p.status = 'active'
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
            WHERE p.status = 'active' AND p.is_self = 0
              AND t.state='open' AND t.prompt_state='active'
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

    @discardableResult
    func beginRecording() -> Bool {
        do {
            try recorder.begin()
            micFailure = nil
            workCollapsed = false    // a new capture is his attention, freshly given
            pendingCapture = .recording
            return true
        } catch {
            pendingCapture = nil   // mic unavailable: the typed note is right there (P3)
            if case RecordingError.denied = error {
                micFailure = .denied
            } else {
                micFailure = .unavailable(String(describing: error))
            }
            return false
        }
    }

    /// The user backed out mid-recording: stop the mic NOW and leave nothing
    /// behind — an open mic after dismiss is a privacy failure (PRIV-1 spirit).
    func cancelRecording() {
        if let ref = try? recorder.end() {
            UserEditService.deleteAudioFile(at: ref)
        }
        pendingCapture = nil
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
        captureNotice = nil
        let primer = knownNamesPrimer()
        do {
            let result = try await transcription.transcribe(audioAt: audioRef, primedWith: primer)
            let event = try edits.captureEvent(.init(
                kind: kind, occurredAt: store.clock.now(),
                transcript: result.text, audioRef: audioRef, participants: participants))
            let vm = TranscriptReviewViewModel(
                eventID: event, text: result.text, usedFullModel: result.usedFullModel,
                matcher: NameMatcher(knownNames: primer), app: self)
            present(.reviewingTranscript(vm))
        } catch {
            // P3: capture never hard-fails. The recording is kept as a captured
            // event (audio only, no transcript) and resumes from the home
            // footer once a model is available.
            _ = try? edits.captureEvent(.init(
                kind: kind, occurredAt: store.clock.now(),
                audioRef: audioRef, participants: participants))
            pendingCapture = nil
            captureNotice = Self.notice(for: error)
            refreshAmbient()
        }
    }

    /// Transcription failures in the user's words. The recording is always
    /// safe — that is the part that matters and the part every line says.
    static func notice(for error: Error) -> String {
        switch error {
        case TranscriptionError.speechDenied: return Copy.speechDenied
        case TranscriptionError.onDeviceUnavailable: return Copy.transcriptionOffDeviceRefused
        case TranscriptionError.noSpeechFound: return Copy.transcriptionNoSpeech
        case TranscriptionError.audioUnreadable: return Copy.transcriptionAudioUnreadable
        case TranscriptionError.recognizerFailed(let detail): return Copy.transcriptionFailed(detail)
        default: return Copy.transcriptionUnavailable
        }
    }

    /// Resume a captured-but-untranscribed memo (audio kept, transcript absent).
    func transcribeExisting(eventID: String) async {
        guard let audioRef = try? store.db.scalar(
            "SELECT raw_audio_ref FROM event WHERE id=? AND lifecycle='captured'",
            [.text(eventID)]).stringValue else {
            // the audio is gone (deleted, or never written) — say so rather
            // than leaving a tap that does nothing
            captureNotice = Copy.memoAudioMissing
            return
        }
        captureNotice = nil
        workCollapsed = false        // he just asked for this one; show him the result
        pendingCapture = .transcribing(audioRef: audioRef)
        let primer = knownNamesPrimer()
        do {
            let result = try await transcription.transcribe(audioAt: audioRef, primedWith: primer)
            try edits.editTranscript(event: eventID, transcript: result.text)
            let vm = TranscriptReviewViewModel(
                eventID: eventID, text: result.text, usedFullModel: result.usedFullModel,
                matcher: NameMatcher(knownNames: primer), app: self)
            present(.reviewingTranscript(vm))
        } catch {
            pendingCapture = nil   // still waiting; still resumable (P10: no nag)
            captureNotice = Self.notice(for: error)
        }
    }

    func transcriptConfirmed(eventID: String, finalText: String, usedFullModel: Bool) {
        try? edits.editTranscript(event: eventID, transcript: finalText)
        // §7.5 gate: audio deleted ONLY when the full model transcribed.
        try? edits.confirmEvent(eventID, fullModelTranscribed: usedFullModel)
        startExtraction(eventID: eventID)
    }

    func startExtraction(eventID: String) {
        workCollapsed = false        // confirming a transcript is a fresh ask
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
            // A run can legitimately produce nothing: INV-7 drops every claim he
            // has already saved, and some memos hold no facts at all. Asking
            // "Does this look right?" over an empty screen is not a question.
            // The event is `fully_resolved` either way (Store.syncStatus with
            // total == 0), so nothing is stranded by not showing it.
            guard !outcome.proposalIDs.isEmpty else {
                pendingCapture = nil
                captureNotice = outcome.suppressedCount > 0
                    ? Copy.nothingNewInCapture : Copy.nothingToStructure
                refreshAmbient()
                return
            }
            present(.reviewingProposals(ReviewViewModel(syncRunID: outcome.syncRunID, app: self)))
        } catch {
            // Sync-later: the event stays confirmed+unsynced, resumable from the
            // home footer (J-11). No nagging (P10).
            pendingCapture = nil
        }
    }

    /// Let a waiting memo go. The ledger is append-only, so this is a lifecycle
    /// transition to `discarded` (never a row delete) — and the write layer
    /// takes the audio file with it, which is the whole point when the file is
    /// the thing that's broken.
    func discard(_ memo: WaitingMemo) {
        guard memo.canDiscard else { return }
        do {
            try edits.discardEvent(memo.id)
            captureNotice = nil
        } catch {
            captureNotice = Copy.memoDiscardFailed
        }
        refreshAmbient()
    }

    /// Resume an unsynced event later (J-11) — proposals identical to immediate sync.
    func syncLater(eventID: String) {
        startExtraction(eventID: eventID)
    }

    /// The ceiling model downloads during onboarding dead time (§6); quiet,
    /// resumed on next launch if it doesn't finish. Once it exists, the
    /// upgrade pass keeps the §7.5 promise: the full model re-listens to any
    /// retained recording, the improved transcript lands as an event amendment
    /// (the confirmed original is frozen, §7.1), and the recording is deleted.
    /// The whisper stage, wherever it sits. Reaching for it with a direct cast
    /// at `transcription` stopped working the moment the cascade wrapped it.
    var whisperTranscriber: WhisperTranscriber? {
        if let whisper = transcription as? WhisperTranscriber { return whisper }
        return (transcription as? CascadingTranscriber)?.whisperStage
    }

    func warmModels() {
        guard let whisper = whisperTranscriber else { return }
        let models = whisper.models
        Task { [weak self] in
            // the Bool is deliberately dropped — the failure streak that
            // noteStalledModelDownload reads is kept by the downloader itself
            _ = await Task.detached(priority: .utility) {
                await models.downloadCeilingIfNeeded()
            }.value
            await self?.upgradeRetainedAudio()
            self?.noteStalledModelDownload(models)
        }
    }

    /// FN-5: a download that never lands has no symptom except recordings
    /// piling up, because §7.5 keeps every one of them until the ceiling model
    /// has listened. After several launches that is worth one plain line — and
    /// only if audio is actually accumulating, so a phone that simply never
    /// needed the model stays quiet (P10).
    func noteStalledModelDownload(_ models: ModelManager) {
        guard models.ceilingURL == nil, models.consecutiveDownloadFailures >= 3 else { return }
        guard awaitingReListen > 0 else { return }
        captureNotice = Copy.modelDownloadStalled
    }

    func upgradeRetainedAudio() async {
        guard let whisper = whisperTranscriber,
              whisper.models.ceilingURL != nil else { return }
        let rows = (try? store.db.query(
            "SELECT id, raw_audio_ref FROM event WHERE lifecycle='confirmed' AND raw_audio_ref IS NOT NULL"
        )) ?? []
        let primer = knownNamesPrimer()
        for row in rows {
            guard let event = row.text("id"), let audio = row.text("raw_audio_ref") else { continue }
            // The ceiling really can vanish mid-pass (the file is deletable), and
            // there is no point re-transcribing the rest through the floor when it
            // has — but that is a question about the model, not about this row, so
            // ask it directly instead of inferring it from one row's result.
            guard whisper.models.ceilingURL != nil else { return }
            do {
                let result = try await transcription.transcribe(audioAt: audio, primedWith: primer)
                // A floor-model transcript must never amend-and-delete (§7.5). One
                // recording the ceiling can't read (corrupt, truncated) is that
                // recording's problem: it stays retained and the pass moves on
                // rather than stranding every memo behind it.
                guard result.usedFullModel else { continue }
                try edits.amendEvent(event, field: "transcript", newValue: result.text,
                                     reason: "full-model re-listen (§6) — recording deleted")
                try edits.deleteAudioAfterUpgrade(event: event)
            } catch {
                continue   // that recording stays retained; retried next launch
            }
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
        // The key lives in the keychain, entered once in settings. One
        // provider now (BUILD §1.3 as revised 2026-08-07 — Abdoul's credits are
        // OpenAI); data-retention posture per §1.3 applies to it. Nothing
        // outside OrbitPipeline knows which provider ran (§7.9), which is what
        // keeps this a one-file change if that ever moves.
        if let extractor = ExtractionProvider.fromEnvironment(
            openAIKey: KeychainLite.read("openai-api-key")) {
            return extractor
        }
        return UnavailableExtractor()
    }

    func knownNamesPrimer() -> [String] {
        let names = ((try? store.db.query(
            """
            SELECT display_name FROM person WHERE status != 'merged'
              AND NOT EXISTS (SELECT 1 FROM person_retirement r WHERE r.person_id = person.id)
            """)) ?? [])
            .compactMap { $0.text("display_name") }
        // FIELD-NOTES FN-19: a pointer-shaped name ("his brother") must never be
        // fed to whisper as a name to listen for, or to the extractor as a
        // contact to match against — that is how the string spreads. The write
        // funnel refuses to create them now, but older rows may already hold one.
        let aliases = ((try? store.db.query("SELECT alias FROM person_alias")) ?? [])
            .compactMap { $0.text("alias") }
        return (names + aliases).filter { UserEditService.relationshipPointer(in: $0) == nil }
    }

    func extractionContext(eventID: String) -> ExtractionContext {
        let people = ((try? store.db.query(
            """
            SELECT id, display_name FROM person WHERE status != 'merged' AND is_self = 0
              AND NOT EXISTS (SELECT 1 FROM person_retirement r WHERE r.person_id = person.id)
            """)) ?? [])
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
