import Foundation

struct StackLayer: Codable, Equatable, Identifiable, Sendable {
    struct Size: Codable, Equatable, Sendable {
        var additions: Int
        var deletions: Int
        var changedFiles: Int
    }

    var url: String
    var number: Int
    var title: String
    var author: String
    var isDraft: Bool
    var headRefName: String
    var baseRefName: String
    var headSha: String
    var baseSha: String
    var size: Size?

    var id: Int { number }
}

struct PRStack: Codable, Equatable, Sendable {
    var layers: [StackLayer]
    var currentIndex: Int

    static let maximumLayers = 32

    var current: StackLayer { layers[currentIndex] }

    var position: String { "Part \(currentIndex + 1) of \(layers.count)" }

    func layer(offset: Int) -> StackLayer? {
        let index = currentIndex + offset
        guard layers.indices.contains(index) else { return nil }
        return layers[index]
    }

    static func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.hasPrefix("/"), !name.hasSuffix("/"),
            !name.hasSuffix("."), !name.hasSuffix(".lock"), !name.contains(".."), !name.contains("@{"),
            !name.contains("//")
        else { return false }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.hasPrefix(".") }) else { return false }
        let forbidden: Set<Character> = [" ", "~", "^", ":", "?", "*", "[", "\\"]
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7f && !forbidden.contains(Character(scalar))
        }
    }
}
