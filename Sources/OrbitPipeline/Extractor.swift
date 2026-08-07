import Foundation
import OrbitCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What extraction needs to know beyond the transcript: capture context plus the
/// known-name/entity primers (§7.7 matching, PIPE-1's name-match assist).
public struct ExtractionContext: Sendable {
    public var eventKind: String
    public var capturedAt: String
    public var knownPeople: [(id: String, name: String)]
    public var knownEntities: [(id: String, name: String, aliases: [String])]
    public var selfName: String
    public var selfAnchors: [String]     // era-anchor registry lines (§7.12)
    public init(eventKind: String, capturedAt: String,
                knownPeople: [(id: String, name: String)] = [],
                knownEntities: [(id: String, name: String, aliases: [String])] = [],
                selfName: String = "", selfAnchors: [String] = []) {
        self.eventKind = eventKind
        self.capturedAt = capturedAt
        self.knownPeople = knownPeople
        self.knownEntities = knownEntities
        self.selfName = selfName
        self.selfAnchors = selfAnchors
    }
}

/// What a single extraction cost and how it was configured.
///
/// Recorded on every live fixture because a measurement you cannot reproduce is
/// an anecdote: without the decode parameters, two runs that disagree cannot be
/// told apart from two runs that were configured differently. Latency feeds
/// PERF-5 (≤ 20s for a 3-minute memo) at zero extra cost.
public struct ExtractionTelemetry: Sendable, Codable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var latencySeconds: Double
    public var attempts: Int
    /// Exactly what was sent, as sent. Not what we intended to send.
    public var decodeParams: [String: String]
    /// Parameters the endpoint rejected and we retried without. A silent drop
    /// here would be the same defect as the prompt-version allow-list (FN-35):
    /// a configuration that quietly differs from the one you asked for.
    public var decodeParamsRejected: [String]

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case latencySeconds = "latency_seconds"
        case attempts
        case decodeParams = "decode_params"
        case decodeParamsRejected = "decode_params_rejected"
    }

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil,
                totalTokens: Int? = nil, latencySeconds: Double = 0,
                attempts: Int = 1, decodeParams: [String: String] = [:],
                decodeParamsRejected: [String] = []) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.latencySeconds = latencySeconds
        self.attempts = attempts
        self.decodeParams = decodeParams
        self.decodeParamsRejected = decodeParamsRejected
    }
}

public struct ExtractionResult: Sendable {
    public var payload: ExtractionPayload
    public var modelID: String
    public var promptVersion: String
    public var telemetry: ExtractionTelemetry?
    public init(payload: ExtractionPayload, modelID: String, promptVersion: String,
                telemetry: ExtractionTelemetry? = nil) {
        self.payload = payload
        self.modelID = modelID
        self.promptVersion = promptVersion
        self.telemetry = telemetry
    }
}

/// The §7.9 seam. Nothing outside this file may know whether the model is local
/// or remote; when on-device models suffice, RemoteExtractor ages out and the
/// privacy promise tightens.
public protocol Extractor: Sendable {
    func extract(transcript: String, context: ExtractionContext) async throws -> ExtractionResult
}

public enum ExtractorError: Error {
    case transport(String)
    case badResponse(String)
    case missingFixture(String)
}

// MARK: - Replay (fixtures; deterministic CI)

/// Replays recorded extraction fixtures — Decision 3 applied to evals: every
/// extraction is a cache, recorded with model_id + prompt version, diffable forever.
public struct ReplayExtractor: Extractor {
    public var fixturesDirectory: URL
    public var keyForTranscript: @Sendable (String) -> String

    public init(fixturesDirectory: URL,
                keyForTranscript: @escaping @Sendable (String) -> String) {
        self.fixturesDirectory = fixturesDirectory
        self.keyForTranscript = keyForTranscript
    }

    public struct Fixture: Codable {
        public var modelID: String
        public var promptVersion: String
        public var payload: ExtractionPayload
        enum CodingKeys: String, CodingKey {
            case modelID = "model_id"
            case promptVersion = "prompt_version"
            case payload
        }
    }

    public func extract(transcript: String, context: ExtractionContext) async throws -> ExtractionResult {
        let key = keyForTranscript(transcript)
        let url = fixturesDirectory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else {
            throw ExtractorError.missingFixture(url.path)
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        return ExtractionResult(payload: fixture.payload, modelID: fixture.modelID,
                                promptVersion: fixture.promptVersion)
    }
}

/// The one user-message builder — PRIV-4's audit surface. Both remote
/// extractors send exactly this and nothing more: capture context, owner +
/// era anchors, known-name/entity primers, transcript.
enum ExtractionMessage {
    static func user(transcript: String, context: ExtractionContext) -> String {
        var lines: [String] = []
        lines.append("Capture context: kind=\(context.eventKind), captured_at=\(context.capturedAt)")
        lines.append("Owner: \(context.selfName)")
        if !context.selfAnchors.isEmpty {
            lines.append("Owner era anchors:\n" + context.selfAnchors.map { "  - \($0)" }.joined(separator: "\n"))
        }
        if !context.knownPeople.isEmpty {
            lines.append("Known contacts:\n" + context.knownPeople.map { "  - \($0.name) [\($0.id)]" }.joined(separator: "\n"))
        }
        if !context.knownEntities.isEmpty {
            lines.append("Known entities:\n" + context.knownEntities.map {
                "  - \($0.name) [\($0.id)] aliases: \($0.aliases.joined(separator: ", "))"
            }.joined(separator: "\n"))
        }
        lines.append("Transcript:\n<<<\n\(transcript)\n>>>")
        return lines.joined(separator: "\n\n")
    }
}

// MARK: - The prompt

/// The versioned extraction prompt, shared by every extractor.
///
/// **v2 and v3 were promoted without their golden runs** — BUILD §1.3 requires one
/// on the same commit, and Abdoul waived it explicitly (2026-08-06, in chat;
/// registered in WORKLOG and RATIFICATION §4.16).
///
/// `ORBIT_PROMPT_VERSION=v1` restores an earlier prompt for comparison. The
/// allow-list this replaces silently downgraded any unrecognised value to v3 —
/// so promoting v4 changed the default, the build succeeded, a live measurement
/// ran, and every fixture came back stamped `v3` (FN-35). A validation that
/// quietly substitutes a *different* input is worse than none: it cannot be told
/// apart from the thing working. An unknown version now fails loudly, naming the
/// resource it wanted.
public enum ExtractionPrompt {
    public static var version: String {
        ProcessInfo.processInfo.environment["ORBIT_PROMPT_VERSION"] ?? Self.latestVersion
    }

    /// Highest `extraction-prompt-vN.md` actually bundled — derived, so adding a
    /// prompt is one file rather than a file plus a list to remember.
    public static var latestVersion: String {
        let versions = (Bundle.module.urls(forResourcesWithExtension: "md",
                                           subdirectory: "Resources") ?? [])
            .compactMap { url -> Int? in
                let name = url.deletingPathExtension().lastPathComponent
                guard name.hasPrefix("extraction-prompt-v") else { return nil }
                return Int(name.dropFirst("extraction-prompt-v".count))
            }
        return "v\(versions.max() ?? 1)"
    }

    public static func system() throws -> String {
        guard let url = Bundle.module.url(forResource: "extraction-prompt-\(version)",
                                          withExtension: "md", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ExtractorError.badResponse(
                "no bundled prompt for ORBIT_PROMPT_VERSION=\(version) "
                + "(expected Resources/extraction-prompt-\(version).md)")
        }
        return text
    }
}

// MARK: - Decode parameters

/// Decode parameters, pinned and recorded.
///
/// EVALS §3.5 requires that "model and decode parameters are pinned per release
/// for CI reproducibility". Until 2026-08-07 only `max_tokens` was set and
/// temperature was whatever the provider defaulted to — which is the most likely
/// direct cause of the run-to-run variance in FN-37.
///
/// `seed` is the honest lever here: OpenAI documents it as best-effort, not a
/// guarantee, so pinning it narrows variance without pretending to remove it.
/// Temperature is deliberately **unset by default** — reasoning-tier models
/// reject a non-default value outright, and a run that 400s is worse than a run
/// with provider defaults. Set `ORBIT_TEMPERATURE` to pin it where the model
/// allows. Whatever is actually sent is recorded on the fixture either way.
public struct DecodeParams: Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var seed: Int?
    public var maxTokens: Int

    public static func fromEnvironment() -> DecodeParams {
        let env = ProcessInfo.processInfo.environment
        return DecodeParams(
            temperature: env["ORBIT_TEMPERATURE"].flatMap(Double.init),
            topP: env["ORBIT_TOP_P"].flatMap(Double.init),
            seed: env["ORBIT_SEED"].flatMap(Int.init) ?? 20260807,
            maxTokens: env["ORBIT_MAX_TOKENS"].flatMap(Int.init) ?? 16000)
    }

    func applied(to body: inout [String: Any], dropping dropped: Set<String>) -> [String: String] {
        var recorded: [String: String] = [:]
        func put(_ key: String, _ value: Any?, _ text: String?) {
            guard let value, let text, !dropped.contains(key) else { return }
            body[key] = value
            recorded[key] = text
        }
        put("temperature", temperature, temperature.map { "\($0)" })
        put("top_p", topP, topP.map { "\($0)" })
        put("seed", seed, seed.map { "\($0)" })
        put("max_completion_tokens", maxTokens, "\(maxTokens)")
        return recorded
    }
}

// MARK: - OpenAI (the production endpoint, §7.9)

/// OpenAI-backed extractor — the sole configured provider (BUILD §1.3, revised
/// 2026-08-07: Abdoul's API credits are OpenAI, so the alternate became the
/// primary and the Anthropic path was removed rather than left as dead code
/// that no measurement would ever cover). PRIV-2's single-egress budget points
/// at exactly this host. The rest of the system cannot tell which provider ran —
/// that is the §7.9 seam's whole point, and it is what makes swapping back a
/// one-file change if the credits ever change.
public struct OpenAIExtractor: Extractor {
    public var apiKey: String
    public var model: String
    public var baseURL: URL
    public var decode: DecodeParams
    /// Attempts per extraction, total. Unattended k-run jobs make a transient
    /// timeout a certainty rather than a risk — one killed a full run on
    /// 2026-08-07 and discarded ten completed extractions with it.
    public var maxAttempts: Int

    public static var promptVersion: String { ExtractionPrompt.version }

    public init(apiKey: String,
                model: String = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.1",
                baseURL: URL = URL(string: "https://api.openai.com")!,
                decode: DecodeParams = .fromEnvironment(),
                maxAttempts: Int = 4) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.decode = decode
        self.maxAttempts = maxAttempts
    }

    private func body(transcript: String, context: ExtractionContext,
                      dropping dropped: Set<String>) throws -> ([String: Any], [String: String]) {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": try ExtractionPrompt.system()],
                ["role": "user",
                 "content": ExtractionMessage.user(transcript: transcript, context: context)],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "orbit_extraction",
                    "strict": true,   // the schema is strict-compatible: every object closed + fully required, nullables typed
                    "schema": ExtractionSchema.jsonSchema,
                ],
            ],
        ]
        let recorded = decode.applied(to: &body, dropping: dropped)
        return (body, recorded)
    }

    public func extract(transcript: String, context: ExtractionContext) async throws -> ExtractionResult {
        let started = Date()
        var dropped: Set<String> = []
        var attempt = 0
        var lastError: Error = ExtractorError.transport("no attempt made")

        while attempt < maxAttempts {
            attempt += 1
            let (bodyDict, recorded) = try body(transcript: transcript, context: context,
                                                dropping: dropped)
            var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
            request.httpMethod = "POST"
            request.timeoutInterval = 300
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ExtractorError.badResponse("no HTTP response")
                }
                if http.statusCode != 200 {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    // A rejected decode parameter is retried without it — and
                    // recorded. Dropping it silently would reproduce FN-35.
                    if http.statusCode == 400,
                       let offending = ["temperature", "top_p", "seed", "max_completion_tokens"]
                        .first(where: { text.contains($0) && !dropped.contains($0) }) {
                        dropped.insert(offending)
                        continue
                    }
                    let retryable = http.statusCode == 429 || (500...599).contains(http.statusCode)
                    let err = ExtractorError.transport(
                        "extraction endpoint HTTP \(http.statusCode): \(text.prefix(300))")
                    if retryable, attempt < maxAttempts {
                        lastError = err
                        try await Self.backoff(attempt)
                        continue
                    }
                    throw err
                }
                guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = top["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any] else {
                    throw ExtractorError.badResponse("no message in response")
                }
                if let refusal = message["refusal"] as? String, !refusal.isEmpty {
                    throw ExtractorError.badResponse("endpoint refused the request")
                }
                guard let text = message["content"] as? String else {
                    throw ExtractorError.badResponse("no message content in response")
                }
                let payload = try JSONDecoder().decode(ExtractionPayload.self, from: Data(text.utf8))
                let usage = top["usage"] as? [String: Any]
                let telemetry = ExtractionTelemetry(
                    promptTokens: usage?["prompt_tokens"] as? Int,
                    completionTokens: usage?["completion_tokens"] as? Int,
                    totalTokens: usage?["total_tokens"] as? Int,
                    latencySeconds: Date().timeIntervalSince(started),
                    attempts: attempt,
                    decodeParams: recorded,
                    decodeParamsRejected: dropped.sorted())
                return ExtractionResult(payload: payload, modelID: model,
                                        promptVersion: ExtractionPrompt.version,
                                        telemetry: telemetry)
            } catch let error as ExtractorError {
                throw error
            } catch {
                // Transport-level: timeouts and connection resets. These are the
                // ones that killed the 2026-08-07 run.
                lastError = error
                if attempt < maxAttempts {
                    try await Self.backoff(attempt)
                    continue
                }
            }
        }
        throw lastError
    }

    /// Exponential backoff with jitter, so a rate-limited fleet does not
    /// synchronise its retries into a second thundering herd.
    private static func backoff(_ attempt: Int) async throws {
        let base = pow(2.0, Double(attempt)) * 1.5           // 3s, 6s, 12s
        let jitter = Double.random(in: 0...(base * 0.25))
        try await Task.sleep(nanoseconds: UInt64((base + jitter) * 1_000_000_000))
    }
}

/// Provider selection, in one place. One provider, one key (BUILD §1.3 as
/// revised 2026-08-07). No key → nil, and capture waits for sync-later rather
/// than hard-failing (P3).
public enum ExtractionProvider {
    public static func fromEnvironment(openAIKey: String?) -> Extractor? {
        if let key = openAIKey, !key.isEmpty { return OpenAIExtractor(apiKey: key) }
        return nil
    }
}
