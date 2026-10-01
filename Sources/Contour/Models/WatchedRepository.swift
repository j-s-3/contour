import Foundation

struct WatchedRepository: Codable, Equatable, Identifiable, Sendable {
    var owner: String
    var name: String

    var id: String { "\(owner)/\(name)" }

    var url: URL? { URL(string: "https://github.com/\(owner)/\(name)") }

    func matches(_ other: String) -> Bool {
        id.caseInsensitiveCompare(other) == .orderedSame
    }

    static let maximumOwnerLength = 39
    static let maximumNameLength = 100

    private static let hostMarker = "github.com/"
    private static let acceptedHostPrefixes: Set<String> = [
        "", "https://", "http://", "https://www.", "http://www.", "www.",
    ]
    private static let allowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")

    static func parse(_ input: String) -> WatchedRepository? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: Substring
        let isLink: Bool
        if let host = trimmed.range(of: hostMarker, options: .caseInsensitive) {
            let prefix = trimmed[..<host.lowerBound].lowercased()
            guard acceptedHostPrefixes.contains(prefix) else { return nil }
            path = trimmed[host.upperBound...]
            isLink = true
        } else {
            guard !trimmed.contains("://") else { return nil }
            path = trimmed[...]
            isLink = false
        }

        let leadingSlash = path.hasPrefix("/")
        let parts = path.split(separator: "/").map(String.init)
        guard !leadingSlash, parts.count >= 2, isLink || parts.count == 2 else { return nil }

        let owner = parts[0]
        var name = String(parts[1].prefix { $0 != "?" && $0 != "#" })
        if name.hasSuffix(".git") { name.removeLast(4) }

        guard isValid(owner, maximumLength: maximumOwnerLength), !owner.hasPrefix("-"),
            isValid(name, maximumLength: maximumNameLength), name != ".", name != ".."
        else { return nil }
        return WatchedRepository(owner: owner, name: name)
    }

    private static func isValid(_ text: String, maximumLength: Int) -> Bool {
        !text.isEmpty && text.count <= maximumLength
            && text.unicodeScalars.allSatisfy(allowedCharacters.contains)
    }
}
