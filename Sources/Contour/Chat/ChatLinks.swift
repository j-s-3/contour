import Foundation

enum ChatLinks {
    static let scheme = "contour"

    enum Target: Equatable {
        case code(CodeRef)
        case node(ReviewSubject)
    }

    static func url(for ref: CodeRef) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "code"
        c.queryItems = [
            URLQueryItem(name: "path", value: ref.path),
            URLQueryItem(name: "start", value: String(ref.startLine)),
            URLQueryItem(name: "end", value: String(ref.endLine)),
            URLQueryItem(name: "side", value: ref.side.rawValue),
        ]
        return c.url
    }

    static func url(kind: String, id: String) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "node"
        c.queryItems = [URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "id", value: id)]
        return c.url
    }

    static func target(for url: URL) -> Target? {
        guard url.scheme == scheme, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func q(_ name: String) -> String? { c.queryItems?.first { $0.name == name }?.value }
        switch c.host {
        case "code":
            guard let path = q("path"), let start = q("start").flatMap(Int.init) else { return nil }
            let end = q("end").flatMap(Int.init) ?? start
            return .code(
                CodeRef(
                    path: path, startLine: start, endLine: max(start, end),
                    side: RefSide(rawValue: q("side") ?? "") ?? .head))
        case "node":
            guard let kind = q("kind"), let id = q("id"), let subject = subject(kind: kind, id: id) else { return nil }
            return .node(subject)
        default:
            return nil
        }
    }

    static func subject(kind: String, id: String) -> ReviewSubject? {
        switch kind.lowercased() {
        case "component": return .component(id)
        case "relationship", "edge": return .relationship(id)
        case "decision": return .decision(id)
        case "flow": return .flow(id)
        case "entry", "entrypoint": return .entryPoint(id)
        default: return nil
        }
    }

    private static let codePattern = try! NSRegularExpression(
        pattern: #"`?((?:[\w.\-]+/)*[\w\-]+(?:\.[\w\-]+)*\.[A-Za-z][A-Za-z0-9]{0,9}):(\d+)(?:\s*[-–]\s*L?(\d+))?`?"#
    )
    private static let nodePattern = try! NSRegularExpression(pattern: #"\[\[([a-zA-Z]+):([^\]\s]+)\]\]"#)

    static func linkify(
        _ text: String,
        resolve: (String) -> String?,
        title: (ReviewSubject) -> String?
    ) -> String {
        var out = replace(nodePattern, in: text) { groups in
            guard let subject = subject(kind: groups[1], id: groups[2]),
                let name = title(subject), let url = url(kind: groups[1], id: groups[2])
            else { return nil }
            return "[\(escape(name))](\(url.absoluteString))"
        }
        out = replace(codePattern, in: out) { groups in
            guard let path = resolve(groups[1]), let start = Int(groups[2]) else { return nil }
            let end = Int(groups[3]) ?? start
            let ref = CodeRef(path: path, startLine: start, endLine: max(start, end))
            guard let url = url(for: ref) else { return nil }
            let label = groups[3].isEmpty ? "\(groups[1]):\(start)" : "\(groups[1]):\(start)–\(end)"
            return "[`\(label)`](\(url.absoluteString))"
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, _ transform: ([String]) -> String?)
        -> String
    {
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let prefix = ns.substring(with: NSRange(location: 0, length: match.range.location))
            let insideLinkTarget =
                prefix.range(of: "](", options: .backwards).map { r in
                    !prefix[r.upperBound...].contains(")")
                } ?? false
            let suffix = ns.substring(from: match.range.location + match.range.length)
            let isLinkText = prefix.hasSuffix("[") && suffix.hasPrefix("](")
            let groups = (0..<match.numberOfRanges).map { i -> String in
                let r = match.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            guard !insideLinkTarget, !isLinkText, let replacement = transform(groups) else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += replacement
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}

extension PRGraph {
    var citedPaths: [String] {
        var refs: [CodeRef] = []
        refs += components.flatMap { $0.refs }
        refs += decisions.flatMap { $0.allRefs }
        refs += flows.flatMap { f in f.steps.flatMap { $0.refs } }
        refs += entryPoints.flatMap { $0.refs }
        refs += behaviorChanges.flatMap { c in (c.before + c.after).flatMap { $0.refs } }
        return unique(refs.map { $0.path })
    }

    func linkTitle(_ subject: ReviewSubject) -> String? {
        switch subject {
        case .relationship(let id):
            guard let e = resolvedEdges.first(where: { $0.id == id }) else { return nil }
            return "\(component(e.fromId)?.title ?? e.fromId) → \(component(e.toId)?.title ?? e.toId)"
        default:
            return resolve(subject)?.title
        }
    }
}
