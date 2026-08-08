import Foundation

// Foundation's URL path accessors are not the same type on both platforms:
// `lastPathComponent` and `pathExtension` are `String` on Darwin and `String?`
// on Linux, and `deletingPathExtension` is a method there and a property here.
// Each spelling compiles on macOS and fails the Linux core build (FIELD-NOTES
// FN-37), and the app workflow can't catch it because it only builds on macOS.
// `URL.path` is `String` on both, so everything below is plain string work.
// `scripts/lint-writepath.sh` bans the divergent accessors under Sources/ and
// Tests/ so the next person reaches for this instead of rediscovering FN-37.

extension URL {
    /// The last path component — `String` on every platform.
    public var fileNamePortable: String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    /// The last path component with any extension trimmed.
    public var fileStemPortable: String {
        let name = fileNamePortable
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[name.startIndex..<dot])
    }
}
