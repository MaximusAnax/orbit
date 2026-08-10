import Foundation

/// The name-match post-pass — the PRIMARY transcription-correctness mechanism for
/// proper nouns (DATA-MODEL §6, empirically decided 2026-07-27: prompt priming is
/// an assist, this is the mechanism; PIPE-1 is measured after this pass).
///
/// Platform-neutral so it runs in Linux CI; the app calls it during transcript
/// review to underline near-miss names for one-tap fixing before the audio is gone.
public struct NameMatcher: Sendable {
    public struct Suggestion: Equatable, Sendable {
        public let heard: String          // token as transcribed
        public let range: Range<Int>      // UTF-16-ish index range in the transcript (token offsets)
        public let candidate: String      // known name it probably is
        public let distance: Int
    }

    public var knownNames: [String]

    public init(knownNames: [String]) {
        self.knownNames = knownNames
    }

    /// Tokens within edit-distance ≤ threshold of a known name — excluding exact
    /// matches (nothing to fix) and short/common words (noise control).
    public func suggestions(in transcript: String, threshold: Int = 2) -> [Suggestion] {
        var out: [Suggestion] = []
        var offset = 0
        for rawToken in transcript.split(separator: " ", omittingEmptySubsequences: false) {
            let token = rawToken.trimmingCharacters(in: .punctuationCharacters)
            defer { offset += rawToken.count + 1 }
            guard token.count >= 3, token.first?.isUppercase == true else { continue }
            for name in knownNames {
                for part in name.split(separator: " ").map(String.init) {
                    guard part.count >= 3 else { continue }
                    let d = Self.editDistance(token.lowercased(), part.lowercased())
                    if d > 0 && d <= threshold && abs(token.count - part.count) <= threshold {
                        out.append(Suggestion(heard: token,
                                              range: offset..<(offset + rawToken.count),
                                              candidate: name, distance: d))
                    }
                }
            }
        }
        // best candidate per position
        var best: [Int: Suggestion] = [:]
        for s in out {
            if let existing = best[s.range.lowerBound], existing.distance <= s.distance { continue }
            best[s.range.lowerBound] = s
        }
        return best.values.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Within-transcript name-form consistency (PIPE-1b): distinct capitalized
    /// token forms that are near-miss variants of each other.
    public func inconsistentForms(in transcript: String, threshold: Int = 2) -> [[String]] {
        var forms: Set<String> = []
        for rawToken in transcript.split(separator: " ") {
            let token = rawToken.trimmingCharacters(in: .punctuationCharacters)
            if token.count >= 4, token.first?.isUppercase == true {
                forms.insert(token)
            }
        }
        var groups: [[String]] = []
        var used: Set<String> = []
        for a in forms.sorted() {
            guard !used.contains(a) else { continue }
            var group = [a]
            for b in forms.sorted() where b != a && !used.contains(b) {
                if Self.editDistance(a.lowercased(), b.lowercased()) <= threshold {
                    group.append(b)
                    used.insert(b)
                }
            }
            if group.count > 1 {
                used.insert(a)
                groups.append(group)
            }
        }
        return groups
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1,
                             prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
