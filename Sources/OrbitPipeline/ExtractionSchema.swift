import Foundation

/// The structured-output JSON schema shipped as a resource so the same bytes are
/// used by the API request, fixture validation, and the eval harness.
public enum ExtractionSchema {
    public static var jsonSchema: [String: Any] {
        guard let url = Bundle.module.url(forResource: "extraction-schema-v1",
                                          withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["type": "object"]
        }
        return obj
    }
}
