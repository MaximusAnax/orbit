import Foundation
import OrbitCore
import OrbitSQLite
import OrbitStore
import OrbitWrite
import OrbitPipeline

// orbit-evals — the EVALS.md harness CLI.
//
// Division of labor (BUILD.md §4): payload-level contract grading has a T1 twin in
// scripts/dev/measure.py; THIS harness adds what only production code can grade —
// the sync round-trip: fixtures → SyncEngine → real proposals in the real ledger,
// with the INV suite live underneath. Subcommands:
//   measure --replay     fixtures → sync → round-trip checks → summary (CI gate)
//   measure --live       same, via the production endpoint (needs ANTHROPIC_API_KEY)
//   harvest <db>         review_outcome rows → JSONL eval labels (J-12, EVALS §3.2)

struct EvalFailure: Error, CustomStringConvertible { let description: String }

func repoRoot() -> URL {
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { break }
        dir = parent
    }
    return dir
}

struct RoundTripCase {
    let memo: String
    let seedPeople: [(id: String, name: String)]
    let seedAssertions: [(person: String, objectValue: String, verbatim: String)]
    let checks: [(String, (WriteStore, SyncEngine.Outcome) throws -> Bool)]
}

func fixtureCases() -> [RoundTripCase] {
    [
        RoundTripCase(memo: "silence", seedPeople: [], seedAssertions: [], checks: [
            ("silence → zero proposals", { _, outcome in outcome.proposalIDs.isEmpty }),
        ]),
        RoundTripCase(memo: "eliah", seedPeople: [], seedAssertions: [], checks: [
            ("PROPOSE_STATE present exactly once (INV-24 gate passed)", { store, _ in
                try store.db.scalar("SELECT COUNT(*) FROM proposal WHERE op='PROPOSE_STATE'").intValue == 1
            }),
            ("three CREATE_EVENT episodes, none future-dated", { store, _ in
                let rows = try store.db.query("SELECT payload FROM proposal WHERE op='CREATE_EVENT'")
                guard rows.count == 3 else { return false }
                return rows.allSatisfy { row in
                    let payload = row.text("payload") ?? ""
                    return !payload.contains("\"occurred_at\":\"2026-08")
                        && !payload.contains("\"occurred_at\":\"2027")
                }
            }),
            ("self facts flow to the self row, never a new person", { store, _ in
                let rows = try store.db.query("SELECT payload FROM proposal WHERE op='CREATE_PERSON'")
                return rows.allSatisfy { !($0.text("payload") ?? "").lowercased().contains("abdoul") }
            }),
            ("pending proposals wrote nothing to the ledger (INV-5)", { store, _ in
                try store.db.scalar("SELECT COUNT(*) FROM assertion").intValue == 0
            }),
        ]),
        RoundTripCase(
            memo: "contradiction",
            seedPeople: [("person-james", "James")],
            seedAssertions: [("person-james", "Stripe", "works at Stripe")],
            checks: [
                ("contradicted open fact draws a CLOSE proposal, never an overwrite", { store, _ in
                    let closes = try store.db.query(
                        "SELECT rationale FROM proposal WHERE op='CLOSE'")
                    return closes.count == 1
                        && (closes[0].text("rationale") ?? "").lowercased().contains("supersedes")
                }),
                ("the Stripe fact is untouched while the proposal is pending", { store, _ in
                    try store.db.scalar(
                        "SELECT COUNT(*) FROM assertion WHERE object_value='Stripe' AND valid_to IS NULL"
                    ).intValue == 1
                }),
            ]),
        RoundTripCase(
            memo: "correction",
            seedPeople: [("person-priya", "Priya")],
            seedAssertions: [("person-priya", "Google", "works at Google")],
            checks: [
                ("'never worked there' → CORRECT (retraction), not CLOSE", { store, _ in
                    let corrects = try store.db.scalar(
                        "SELECT COUNT(*) FROM proposal WHERE op='CORRECT'").intValue ?? 0
                    return corrects == 1
                }),
            ]),
        RoundTripCase(
            memo: "hardship",
            seedPeople: [], seedAssertions: [],
            checks: [
                ("hardship thread proposed as condition_hardship (INV-20 upstream)", { store, _ in
                    let rows = try store.db.query("SELECT payload FROM proposal WHERE op='OPEN_THREAD'")
                    return rows.count == 1
                        && (rows[0].text("payload") ?? "").contains("condition_hardship")
                }),
            ]),
        RoundTripCase(
            memo: "futureforce",
            seedPeople: [], seedAssertions: [],
            checks: [
                ("the Abdul namesake arrives as DISAMBIGUATE, never CREATE_PERSON", { store, _ in
                    let creates = try store.db.query("SELECT payload FROM proposal WHERE op='CREATE_PERSON'")
                    let hasAbdul = creates.contains { ($0.text("payload") ?? "").contains("Abdul") }
                    let disamb = try store.db.scalar(
                        "SELECT COUNT(*) FROM proposal WHERE op='DISAMBIGUATE'").intValue ?? 0
                    return !hasAbdul && disamb >= 1
                }),
            ]),
    ]
}

func runMeasureReplay() throws {
    let root = repoRoot()
    let fixtures = root.appendingPathComponent("docs/evals/fixtures")
    var failures: [String] = []
    var passed = 0

    for testCase in fixtureCases() {
        let store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        let edits = UserEditService(store)
        _ = try edits.createPerson(displayName: "Abdoul", isSelf: true)
        for seed in testCase.seedPeople {
            try store.db.run(
                "INSERT INTO person (id, display_name, status, created_at) VALUES (?,?, 'active', ?)",
                [.text(seed.id), .text(seed.name), .text("2026-01-01")])
        }
        if !testCase.seedAssertions.isEmpty {
            let seedEvent = try edits.captureEvent(.init(
                kind: .dinner, occurredAt: "2026-01-15T20:00:00Z",
                transcript: "seed",
                participants: testCase.seedAssertions.map { ($0.person, .confirmed, nil) }))
            try edits.confirmEvent(seedEvent, fullModelTranscribed: true)
            let proposals = ProposalResolutionService(store)
            let x = try proposals.recordExtraction(event: seedEvent, version: 1, modelID: "seed",
                                                   promptVersion: "v1", payload: "{}")
            let run = try proposals.openSyncRun(event: seedEvent, extraction: x)
            for seed in testCase.seedAssertions {
                let pid = try proposals.propose(syncRun: run, .init(
                    op: .assert,
                    payloadJSON: try PayloadCoding.encode(AssertPayload(
                        subject: .id(seed.person), predicate: "employment",
                        objectValue: seed.objectValue, verbatim: seed.verbatim)),
                    rationale: "seed"))!
                try proposals.resolve(proposal: pid, .accept)
            }
        }

        let data = try Data(contentsOf: fixtures.appendingPathComponent("\(testCase.memo).json"))
        let fixture = try JSONDecoder().decode(ReplayExtractor.Fixture.self, from: data)
        let meta = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let sourcePath = (meta?["source"] as? String) ?? ""
        let transcript = (try? String(contentsOf: root.appendingPathComponent(sourcePath),
                                      encoding: .utf8)) ?? "…"

        let anchor = try edits.createPerson(displayName: "capture-anchor")
        let event = try edits.captureEvent(.init(
            kind: .portrait, occurredAt: "2026-07-28T21:00:00Z",
            transcript: transcript,
            participants: [(anchor, .about, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: true)

        let engine = SyncEngine(store)
        let outcome = try engine.sync(
            event: event, extractionVersion: 1,
            result: ExtractionResult(payload: fixture.payload,
                                     modelID: fixture.modelID,
                                     promptVersion: fixture.promptVersion))
        for (label, check) in testCase.checks {
            if try check(store, outcome) {
                passed += 1
                print("  ✓ \(testCase.memo): \(label)")
            } else {
                failures.append("\(testCase.memo): \(label)")
                print("  ✗ \(testCase.memo): \(label)")
            }
        }
    }
    print("round-trip: \(passed) passed, \(failures.count) failed")
    if !failures.isEmpty { throw EvalFailure(description: failures.joined(separator: "; ")) }
}

func runHarvest(dbPath: String) throws {
    let db = try Database.openReadOnly(path: dbPath)
    let rows = try db.query(
        """
        SELECT ro.action, ro.rejection_reason, ro.edited_payload, ro.created_at,
               p.op, p.payload, s.event_id
        FROM review_outcome ro
        JOIN proposal p ON p.id = ro.proposal_id
        JOIN sync_run s ON s.id = p.sync_run_id
        ORDER BY ro.created_at
        """)
    for row in rows {
        // (source-event, claim)-scoped labels — EVALS §3.2
        let record: [String: Any] = [
            "source_event": row.text("event_id") ?? "",
            "op": row.text("op") ?? "",
            "claim": row.text("payload") ?? "",
            "label": row.text("action") ?? "",
            "rejection_reason": row.text("rejection_reason") as Any,
            "edited_to": row.text("edited_payload") as Any,
            "at": row.text("created_at") ?? "",
        ]
        let data = try JSONSerialization.data(withJSONObject: record)
        print(String(data: data, encoding: .utf8)!)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "measure":
        if args.contains("--live") {
            guard ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil else {
                throw EvalFailure(description: "measure --live needs ANTHROPIC_API_KEY (BUILD.md §1.3: ZDR org)")
            }
            print("live measurement loop lands with the first key — replay is the CI path")
            exit(2)
        }
        try runMeasureReplay()
    case "harvest":
        guard args.count > 1 else { throw EvalFailure(description: "usage: harvest <db-path>") }
        try runHarvest(dbPath: args[1])
    default:
        print("""
        orbit-evals — Orbit evaluation harness (EVALS.md)
          measure --replay   fixtures → SyncEngine → round-trip checks (CI gate)
          measure --live     production endpoint (ANTHROPIC_API_KEY required)
          harvest <db>       review outcomes → JSONL eval labels (J-12)
        Payload-level contract grading (the PIPE table): scripts/dev/measure.py (T1 twin).
        """)
    }
} catch {
    print("FAIL: \(error)")
    exit(1)
}
