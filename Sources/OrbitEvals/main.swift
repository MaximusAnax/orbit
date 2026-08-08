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
//   measure --live       same, via the production endpoint (needs OPENAI_API_KEY)
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

func runMeasureReplay(fixturesSubdir: String = "docs/evals/fixtures") throws {
    let root = repoRoot()
    let fixtures = root.appendingPathComponent(fixturesSubdir)
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


/// Live measurement (EVALS §9 · MEASUREMENT-REWORK Phase 0+1).
///
/// Collection and grading are deliberately separate. This function only
/// *collects*: k independent runs of the whole corpus through the production
/// endpoint, every run persisted with the decode parameters, token usage,
/// latency and prompt version that produced it. Grading happens afterwards,
/// offline, from that store — which is what makes a collected run re-gradable
/// for free when the grader improves, instead of costing another API bill.
///
///   orbit-evals measure --live [--runs k] [--out DIR] [--concurrency N]
///
/// Checkpointed: an existing, parseable run file is never re-fetched, so a job
/// killed at run 7 of 10 resumes rather than starting over.
func runMeasureLive(runs: Int, concurrency: Int, outLabel: String?) async throws {
    let env = ProcessInfo.processInfo.environment
    guard let key = env["OPENAI_API_KEY"], !key.isEmpty else {
        throw EvalFailure(description:
            "measure --live needs OPENAI_API_KEY (single provider, BUILD.md §1.3 rev. 2026-08-07)")
    }
    let extractor = OpenAIExtractor(apiKey: key)
    let root = repoRoot()
    let fixturesDir = root.appendingPathComponent("docs/evals/fixtures")
    let files = try FileManager.default.contentsOfDirectory(at: fixturesDir,
                                                            includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    struct Memo: Sendable {
        var name: String
        var file: String
        var source: String
        var transcript: String
        var eventKind: String
        var seeds: [(id: String, name: String)]
    }

    // The capture context comes from the fixture metadata, not from a hardcoded
    // set in this file. FN-36: `eventKind` was pinned to "portrait" for every
    // memo, which is a false statement to the model (episodes are portraits-only),
    // and it silently inflated every invention count. Declaring it next to the
    // golden that grades it is what stops that recurring.
    var memos: [Memo] = []
    for file in files {
        let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        guard let source = meta?["source"] as? String,
              let transcript = try? String(contentsOf: root.appendingPathComponent(source),
                                           encoding: .utf8) else {
            print("  ! \(file.lastPathComponent): no readable source transcript — skipped")
            continue
        }
        let name = file.deletingPathExtension().lastPathComponent
            .lowercased().replacingOccurrences(of: " ", with: "-")
        memos.append(Memo(name: name,
                          file: file.lastPathComponent,
                          source: source,
                          transcript: transcript,
                          eventKind: (meta?["event_kind"] as? String) ?? "encounter",
                          seeds: fixtureCases().first { $0.memo == name }?.seedPeople ?? []))
    }
    guard !memos.isEmpty else { throw EvalFailure(description: "no readable corpus memos") }

    let label = outLabel ?? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: Date()) + "-" + extractor.model.replacingOccurrences(of: "/", with: "-")
    }()
    let runsRoot = root.appendingPathComponent("docs/evals/runs/\(label)")
    try FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true)

    print("== collecting \(runs) run(s) × \(memos.count) memos → docs/evals/runs/\(label) ==")
    print("   model \(extractor.model) · prompt \(ExtractionPrompt.version) · concurrency \(concurrency)")

    struct LiveFixture: Encodable {
        var model_id: String
        var prompt_version: String
        var source: String
        var run_index: Int
        var telemetry: ExtractionTelemetry?
        var payload: ExtractionPayload
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    var totalTokens = 0
    var totalSeconds = 0.0
    var failures: [String] = []

    for run in 1...runs {
        let runDir = runsRoot.appendingPathComponent(String(format: "run-%02d", run))
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        // Checkpoint: anything already collected and parseable is left alone.
        let pending = memos.filter { memo in
            let out = runDir.appendingPathComponent(memo.file)
            guard let data = try? Data(contentsOf: out) else { return true }
            return (try? JSONSerialization.jsonObject(with: data)) == nil
        }
        if pending.isEmpty {
            print("  run \(run): already complete — skipped")
            continue
        }

        var done = 0
        for chunk in stride(from: 0, to: pending.count, by: concurrency).map({
            Array(pending[$0..<min($0 + concurrency, pending.count)])
        }) {
            try await withThrowingTaskGroup(of: (String, Result<ExtractionResult, Error>).self) { group in
                for memo in chunk {
                    group.addTask {
                        let context = ExtractionContext(
                            eventKind: memo.eventKind,
                            capturedAt: "2026-07-29T12:00:00Z",
                            knownPeople: memo.seeds,
                            selfName: "Abdoul")
                        do {
                            return (memo.name, .success(
                                try await extractor.extract(transcript: memo.transcript,
                                                            context: context)))
                        } catch {
                            return (memo.name, .failure(error))
                        }
                    }
                }
                for try await (name, outcome) in group {
                    guard let memo = pending.first(where: { $0.name == name }) else { continue }
                    switch outcome {
                    case .success(let result):
                        let fixture = LiveFixture(model_id: result.modelID,
                                                  prompt_version: result.promptVersion,
                                                  source: memo.source,
                                                  run_index: run,
                                                  telemetry: result.telemetry,
                                                  payload: result.payload)
                        try encoder.encode(fixture)
                            .write(to: runDir.appendingPathComponent(memo.file))
                        totalTokens += result.telemetry?.totalTokens ?? 0
                        totalSeconds += result.telemetry?.latencySeconds ?? 0
                        done += 1
                    case .failure(let error):
                        // Recorded, never silently dropped: a missing memo in a
                        // run is a hole in the distribution and the aggregator
                        // must be able to see it.
                        failures.append("run \(run) · \(name): \(error)")
                    }
                }
            }
        }
        print("  run \(run): \(done)/\(pending.count) collected")
    }

    // The manifest is the run's provenance: without it, two runs that disagree
    // cannot be told apart from two runs configured differently.
    //
    // Collection is checkpointed, so this is written more than once for the same
    // label. Rewriting it from scratch each time reported only what THIS process
    // did: a resumed job dropped every failure the first pass recorded and
    // under-counted tokens and latency — the provenance of a resumed run was a
    // record of its last leg. Carry the previous values forward instead.
    let manifestURL = runsRoot.appendingPathComponent("manifest.json")
    let previous = (try? Data(contentsOf: manifestURL))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    let priorFailures = previous["failures"] as? [String] ?? []
    // A resumed leg re-reports nothing it skipped, so the union is the history.
    let allFailures = priorFailures + failures.filter { !priorFailures.contains($0) }
    let manifest: [String: Any] = [
        "label": label,
        "model": extractor.model,
        "prompt_version": ExtractionPrompt.version,
        "runs": runs,
        "memos": memos.map(\.name),
        "git_sha": (try? shell("git rev-parse --short HEAD")) ?? "unknown",
        "collected_at": previous["collected_at"] as? String
            ?? ISO8601DateFormatter().string(from: Date()),
        "last_collected_at": ISO8601DateFormatter().string(from: Date()),
        "total_tokens": (previous["total_tokens"] as? Int ?? 0) + totalTokens,
        "total_seconds": (previous["total_seconds"] as? Double ?? 0) + totalSeconds,
        "failures": allFailures,
    ]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: manifestURL)

    print("""

    collected: \(totalTokens) tokens · \(String(format: "%.0f", totalSeconds))s of model time
    """)
    if !failures.isEmpty {
        print("  \(failures.count) extraction failure(s) recorded in manifest.json:")
        for f in failures.prefix(5) { print("    - \(f)") }
    }
    print("""

    Grade and aggregate (collection and grading are separate on purpose):
      python3 scripts/dev/aggregate.py docs/evals/runs/\(label)
    """)
}

func shell(_ command: String) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    let pipe = Pipe()
    p.standardOutput = pipe
    try p.run()
    p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "measure":
        if args.contains("--live") {
            func intArg(_ name: String, _ fallback: Int) -> Int {
                guard let i = args.firstIndex(of: name), args.count > i + 1,
                      let v = Int(args[i + 1]) else { return fallback }
                return v
            }
            func strArg(_ name: String) -> String? {
                guard let i = args.firstIndex(of: name), args.count > i + 1 else { return nil }
                return args[i + 1]
            }
            try await runMeasureLive(runs: intArg("--runs", 1),
                                     concurrency: max(1, intArg("--concurrency", 3)),
                                     outLabel: strArg("--out"))
        } else if let i = args.firstIndex(of: "--fixtures"), args.count > i + 1 {
            try runMeasureReplay(fixturesSubdir: args[i + 1])
        } else {
            try runMeasureReplay()
        }
    case "harvest":
        guard args.count > 1 else { throw EvalFailure(description: "usage: harvest <db-path>") }
        try runHarvest(dbPath: args[1])
    default:
        print("""
        orbit-evals — Orbit evaluation harness (EVALS.md)
          measure --replay [--fixtures dir]\n                     fixtures → SyncEngine → round-trip checks (CI gate)
          measure --live [--runs k] [--concurrency n] [--out label]\n                     collect k runs via OPENAI_API_KEY → docs/evals/runs/<label>/
          harvest <db>       review outcomes → JSONL eval labels (J-12)
        Payload-level contract grading (the PIPE table): scripts/dev/measure.py (T1 twin).
        """)
    }
} catch {
    print("FAIL: \(error)")
    exit(1)
}
