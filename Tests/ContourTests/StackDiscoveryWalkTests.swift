import Foundation
import Testing

@testable import Contour

struct StackDiscoveryWalkTests {
    private struct Lookups: Sendable {
        var byHead: [String: StackLayer] = [:]
        var byBase: [String: [StackLayer]] = [:]

        func parent(_ base: String) -> StackLayer? { byHead[base] }
        func children(_ head: String) -> [StackLayer] { byBase[head] ?? [] }
    }

    private static func chain(_ names: [String], base: String = "main") -> [StackLayer] {
        var layers: [StackLayer] = []
        var previous = base
        for (index, name) in names.enumerated() {
            layers.append(PRStackTests.layer(index + 1, head: name, base: previous))
            previous = name
        }
        return layers
    }

    private static func lookups(_ layers: [StackLayer]) -> Lookups {
        var lookups = Lookups()
        for layer in layers {
            lookups.byHead[layer.headRefName] = layer
            lookups.byBase[layer.baseRefName, default: []].append(layer)
        }
        return lookups
    }

    @Test func openedAtTheBottomTheWalkClimbsToTheTop() async throws {
        let layers = Self.chain(["a", "b", "c"])
        let lookups = Self.lookups(layers)
        let stack = try await StackDiscovery.walk(
            current: layers[0], parent: lookups.parent, children: lookups.children)
        #expect(stack?.layers.map(\.number) == [1, 2, 3])
        #expect(stack?.currentIndex == 0)
    }

    @Test func openedInTheMiddleTheWalkFindsBothDirections() async throws {
        let layers = Self.chain(["a", "b", "c"])
        let lookups = Self.lookups(layers)
        let stack = try await StackDiscovery.walk(
            current: layers[1], parent: lookups.parent, children: lookups.children)
        #expect(stack?.layers.map(\.number) == [1, 2, 3])
        #expect(stack?.currentIndex == 1)
    }

    @Test func openedAtTheTopTheWalkDescendsToTheTrunk() async throws {
        let layers = Self.chain(["a", "b", "c"])
        let lookups = Self.lookups(layers)
        let stack = try await StackDiscovery.walk(
            current: layers[2], parent: lookups.parent, children: lookups.children)
        #expect(stack?.layers.map(\.number) == [1, 2, 3])
        #expect(stack?.currentIndex == 2)
    }

    @Test func aLayerWithNoParentAndNoChildIsNotAStack() async throws {
        let alone = PRStackTests.layer(9, head: "solo", base: "main")
        let stack = try await StackDiscovery.walk(current: alone, parent: { _ in nil }, children: { _ in [] })
        #expect(stack == nil)
    }

    @Test func aForkAboveEndsTheUpwardWalkAtTheFork() async throws {
        var layers = Self.chain(["a", "b"])
        layers.append(PRStackTests.layer(3, head: "c", base: "b"))
        layers.append(PRStackTests.layer(4, head: "d", base: "b"))
        let lookups = Self.lookups(layers)
        let stack = try await StackDiscovery.walk(
            current: layers[0], parent: lookups.parent, children: lookups.children)
        #expect(stack?.layers.map(\.number) == [1, 2])
    }

    @Test func anInvalidBaseBranchIsNeverLookedUp() async throws {
        let odd = PRStackTests.layer(1, head: "h", base: "-rf")
        let child = PRStackTests.layer(2, head: "i", base: "h")
        let stack = try await StackDiscovery.walk(
            current: odd,
            parent: { _ in
                Issue.record("parent lookup must not run for an invalid branch name")
                return nil
            },
            children: { $0 == "h" ? [child] : [] })
        #expect(stack?.layers.map(\.number) == [1, 2])
    }

    @Test func anInvalidHeadBranchIsNeverLookedUpForChildren() async throws {
        let odd = PRStackTests.layer(2, head: "a..b", base: "a")
        let parent = PRStackTests.layer(1, head: "a", base: "main")
        let stack = try await StackDiscovery.walk(
            current: odd,
            parent: { $0 == "a" ? parent : nil },
            children: { _ in
                Issue.record("child lookup must not run for an invalid branch name")
                return []
            })
        #expect(stack?.layers.map(\.number) == [1, 2])
    }

    @Test func aCycleEndsTheWalk() async throws {
        let a = PRStackTests.layer(1, head: "a", base: "b")
        let b = PRStackTests.layer(2, head: "b", base: "a")
        let stack = try await StackDiscovery.walk(
            current: a, parent: { base in base == "b" ? b : (base == "a" ? a : nil) }, children: { _ in [] })
        #expect(stack?.layers.map(\.number) == [2, 1])
    }

    @Test func aChildThatWasAlreadySeenEndsTheUpwardWalk() async throws {
        let a = PRStackTests.layer(1, head: "a", base: "main")
        let stack = try await StackDiscovery.walk(
            current: a, parent: { _ in nil }, children: { $0 == "a" ? [a] : [] })
        #expect(stack == nil)
    }

    @Test func theWalkIsCappedAtTheMaximumNumberOfLayers() async throws {
        let names = (1...40).map { "l\($0)" }
        let layers = Self.chain(names)
        let lookups = Self.lookups(layers)
        let fromBottom = try await StackDiscovery.walk(
            current: layers[0], parent: lookups.parent, children: lookups.children)
        #expect(fromBottom?.layers.count == PRStack.maximumLayers)
        let fromTop = try await StackDiscovery.walk(
            current: layers[39], parent: lookups.parent, children: lookups.children)
        #expect(fromTop?.layers.count == PRStack.maximumLayers)
        #expect(fromTop?.currentIndex == PRStack.maximumLayers - 1)
    }

    @Test func aThrowingLookupPropagates() async {
        struct Boom: Error {}
        let alone = PRStackTests.layer(9, head: "solo", base: "main")
        await #expect(throws: Boom.self) {
            try await StackDiscovery.walk(current: alone, parent: { _ in throw Boom() }, children: { _ in [] })
        }
    }
}
