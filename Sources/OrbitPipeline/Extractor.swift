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

public struct ExtractionResult: Sendable {
    public var payload: ExtractionPayload
    public var modelID: String
    public var promptVersion: String
    public init(payload: ExtractionPayload, modelID: String, promptVersion: String) {
        self.payload = payload
        self.modelID = modelID
        self.promptVersion = promptVersion
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

// MARK: - Remote (the production endpoint)

/// Claude API client. Requirements carried from BUILD.md §1.3: the org runs under
/// zero data retention (Fable-tier models are structurally excluded — they cannot
/// run under ZDR); the transcript is the only content that leaves the device;
/// PRIV-2's single-egress budget points at exactly this host.
public struct RemoteExtractor: Extractor {
    public var apiKey: String
    public var model: String
    public var baseURL: URL

    /// The active prompt version.
    ///
    /// **v2 and v3 were promoted without their golden runs** — BUILD §1.3 requires one on
    /// the same commit, and Abdoul waived it explicitly (2026-08-06, in chat;
    /// registered in WORKLOG and RATIFICATION §4.16). The waiver is recorded
    /// rather than quietly taken, because the consequence is real: the
    /// provisional PIPE numbers were all measured against v1 fixtures, so they
    /// describe the *previous* prompt until a live run re-measures this one.
    ///
    /// `ORBIT_PROMPT_VERSION=v1` restores the measured prompt for comparison.
    public static var promptVersion: String {
        let requested = ProcessInfo.processInfo.environment["ORBIT_PROMPT_VERSION"] ?? "v3"
        return ["v1", "v2", "v3"].contains(requested) ? requested : "v3"
    }

    public init(apiKey: String, model: String = "claude-opus-5",
                baseURL: URL = URL(string: "https://api.anthropic.com")!) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    static func systemPrompt() throws -> String {
        guard let url = Bundle.module.url(forResource: "extraction-prompt-\(promptVersion)",
                                          withExtension: "md", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ExtractorError.badResponse("missing extraction prompt resource")
        }
        return text
    }

    func userMessage(transcript: String, context: ExtractionContext) -> String {
        ExtractionMessage.user(transcript: transcript, context: context)
    }

    public func extract(transcript: String, context: ExtractionContext) async throws -> ExtractionResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": try Self.systemPrompt(),
            "messages": [["role": "user", "content": userMessage(transcript: transcript, context: context)]],
            "output_config": ["format": [
                "type": "json_schema",
                "schema": ExtractionSchema.jsonSchema,
            ]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ExtractorError.transport("extraction endpoint HTTP error: \(text.prefix(300))")
        }
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractorError.badResponse("non-JSON response")
        }
        if let stop = top["stop_reason"] as? String, stop == "refusal" {
            throw ExtractorError.badResponse("endpoint refused the request")
        }
        guard let content = top["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            throw ExtractorError.badResponse("no text block in response")
        }
        let payload = try JSONDecoder().decode(ExtractionPayload.self, from: Data(text.utf8))
        return ExtractionResult(payload: payload, modelID: model, promptVersion: Self.promptVersion)
    }
}

// MARK: - OpenAI (alternate remote endpoint, §7.9)

/// OpenAI-backed extractor — same versioned prompt, same JSON schema, same
/// single-egress budget (PRIV-2 applies to whichever endpoint is configured;
/// verify the org's data-retention posture before production use, BUILD §1.3).
/// The rest of the system cannot tell which provider ran — that is the seam's
/// whole point.
public struct OpenAIExtractor: Extractor {
    public var apiKey: String
    public var model: String
    public var baseURL: URL

    public static let promptVersion = RemoteExtractor.promptVersion

    public init(apiKey: String,
                model: String = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.1",
                baseURL: URL = URL(string: "https://api.openai.com")!) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    public func extract(transcript: String, context: ExtractionContext) async throws -> ExtractionResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": try RemoteExtractor.systemPrompt()],
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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ExtractorError.transport("extraction endpoint HTTP error: \(text.prefix(300))")
        }
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = top["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw ExtractorError.badResponse("no message content in response")
        }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty {
            throw ExtractorError.badResponse("endpoint refused the request")
        }
        let payload = try JSONDecoder().decode(ExtractionPayload.self, from: Data(text.utf8))
        return ExtractionResult(payload: payload, modelID: model, promptVersion: Self.promptVersion)
    }
}

/// Provider selection, in one place: the Anthropic key wins when both exist
/// (the ratified default endpoint); the OpenAI key is the configured
/// alternative (Abdoul, 2026-07-29). No key → nil, capture waits for
/// sync-later.
public enum ExtractionProvider {
    public static func fromEnvironment(anthropicKey: String?, openAIKey: String?) -> Extractor? {
        if let key = anthropicKey, !key.isEmpty { return RemoteExtractor(apiKey: key) }
        if let key = openAIKey, !key.isEmpty { return OpenAIExtractor(apiKey: key) }
        return nil
    }
}
