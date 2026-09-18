import Foundation

public struct BookmarkParseIssue: Equatable, Sendable {
    /// Root key and child indices identify the malformed node without exposing its contents.
    public let location: String
    public let message: String
}

public struct BookmarkParseResult: Sendable {
    public let bookmarks: [BookmarkRecord]
    public let issues: [BookmarkParseIssue]
}

public enum BookmarkParser {
    /// Malformed nodes are skipped independently. Invalid JSON or a missing roots object throws.
    /// GUIDs take precedence over native IDs; nodes with neither are skipped to avoid unstable IDs.
    public static func parse(_ data: Data, profile: BrowserProfile) throws -> BookmarkParseResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = object["roots"] as? [String: Any] else {
            throw ChromiumSupportError.invalidBookmarks
        }
        var records: [BookmarkRecord] = []
        var issues: [BookmarkParseIssue] = []
        var seen = Set<String>()

        func issue(_ location: String, _ message: String) {
            issues.append(BookmarkParseIssue(location: location, message: message))
        }

        func visit(_ value: Any, folders: [String], location: String, depth: Int) {
            guard depth <= 256 else {
                issue(location, "Folder nesting exceeds 256 levels")
                return
            }
            guard let node = value as? [String: Any], let type = node["type"] as? String else {
                issue(location, "Missing node type")
                return
            }
            switch type {
            case "folder":
                guard let children = node["children"] as? [Any] else {
                    issue(location, "Missing folder children")
                    return
                }
                let path = depth == 0 ? folders : folders + [node["name"] as? String ?? ""]
                for (index, child) in children.enumerated() {
                    visit(child, folders: path, location: "\(location)/\(index)", depth: depth + 1)
                }
            case "url":
                guard let rawURL = node["url"] as? String,
                      !rawURL.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                      let url = URL(string: rawURL), url.scheme != nil else {
                    issue(location, "Missing or invalid absolute URL")
                    return
                }
                let guid = (node["guid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let nativeID = (node["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                guard let identifier = guid ?? nativeID else {
                    issue(location, "Missing GUID and native ID")
                    return
                }
                let id = stableID([profile.browser.id, profile.directoryName, guid == nil ? "id" : "guid", identifier])
                guard seen.insert(id).inserted else {
                    issue(location, "Duplicate bookmark identity")
                    return
                }
                records.append(BookmarkRecord(id: id, profile: profile, title: node["name"] as? String ?? "",
                                              url: url, guid: guid, nativeID: nativeID, folderPath: folders))
            default:
                issue(location, "Unsupported node type")
            }
        }

        for key in roots.keys.sorted() {
            visit(roots[key]!, folders: [key], location: key, depth: 0)
        }
        return BookmarkParseResult(bookmarks: records, issues: issues)
    }
}
