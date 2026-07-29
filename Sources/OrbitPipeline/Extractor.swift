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

// MARK: - Remote (the production endpoint)

/// Claude API client. Requirements carried from BUILD.md §1.3: the org runs under
/// zero data retention (Fable-tier models are structurally excluded — they cannot
/// run under ZDR); the transcript is the only content that leaves the device;
/// PRIV-2's single-egress budget points at exactly this host.
public struct RemoteExtractor: Extractor {
    public var apiKey: String
    public var model: String
    public var baseURL: URL

    public static let promptVersion = "v1"

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
