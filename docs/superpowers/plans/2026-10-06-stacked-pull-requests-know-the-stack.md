# Stacked Pull Requests, PR 1: Know the Stack — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a reviewer opens a pull request that is one layer of a stack, Contour discovers the whole chain, tells the model where this layer sits, shows the stack in the Overview header, and lets the reviewer move between layers.

**Architecture:** A pure `PRStack` model plus a `StackDiscovery` service (two transports, one pure walk) feed a new `.stack` pipeline event. The pipeline runs discovery beside the checkout and passes the stack to `PromptBuilder`, which adds one block to the context file for stacked pull requests only. `GraphStore` keeps the stack as session state; a `StackStrip` view in the Overview header and two commands move between layers through the existing `load(prURL:)`.

**Tech Stack:** Swift 6.4, SwiftUI, Swift Testing, `gh` CLI and the anonymous GitHub REST API through the existing `Shell` and `AnonymousAPISource` seams.

**Spec:** `docs/superpowers/specs/2026-10-02-stacked-pull-requests-design.md` (sections 1, 2 except "Analyze the whole stack" and the Stack lens, 4, 5 except `StackAnalyzer`, 7, 8, 9, 10). Background analysis, worktrees and the Stack lens are PR 2.

## Global Constraints

- No code comments of any kind in Swift sources or tests, including `// MARK:`.
- Swift 6 language mode on the app target; every compiler warning is an error. A closure crossing isolation needs `@Sendable`.
- Every new or touched file at 90%+ line coverage; the overall figure must not drop.
- Fixtures under `Tests/ContourTests/Fixtures/` are captured real output, never hand-written, with provenance recorded in `Fixtures/README.md`.
- Harness invocation flags are untouched. Author-controlled text (titles, branch names, logins) is rendered verbatim and reaches the prompt only inside `<UNTRUSTED_PR_CONTENT>`.
- Branch names are validated against git's refname rules before they become a `gh` argument, and percent-encoded for REST.
- The context file for a pull request that is not stacked stays byte-identical to today's, so `AnalysisPipeline.pipelineVersion` (17) does not change.
- Format with `swift format --in-place --recursive --parallel Sources Tests Package.swift` before every commit; CI lints with `--strict`.
- Commit messages carry the rationale and end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. **A branch name that is not a valid refname** (leading `-`, `..`, `@{`, control characters, trailing `.lock`) must be treated as "no parent" and never passed to `gh`. Pinned in Task 1 (validator) and Task 2 (walk skips lookup).
2. **A layer whose head is a fork** (`isCrossRepository` true, or REST `head.repo.full_name` not the repository) must be ignored by the parsers, since the chain must stay in one repository. Pinned in Task 2 parse tests.
3. **Discovery that hangs or throws** must never delay the first analysis stage or fail the review. Pinned in Task 4 (grace period test, throwing discovery test).
4. **Opening a layer that is the top or bottom** must disable "next" or "previous" rather than wrap or crash. Pinned in Task 1 (`layer(offset:)` at the ends) and Task 7 (enabled states).
5. **A REST list row without size fields** (the list endpoint returns `additions: null`) must still parse, with the size absent rather than zero. Pinned in Task 2 REST parse test.

---

### Task 1: `PRStack` model and the refname validator

**Files:**
- Create: `Sources/Contour/Models/PRStack.swift`
- Test: `Tests/ContourTests/PRStackTests.swift`

**Interfaces:**
- Produces: `StackLayer`, `StackLayer.Size`, `PRStack`, `PRStack.layer(offset:)`, `PRStack.position`, `PRStack.isValidBranchName(_:)`, `PRStack.maximumLayers`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import Contour

struct PRStackTests {
    static func layer(_ number: Int, head: String, base: String) -> StackLayer {
        StackLayer(
            url: "https://github.com/acme/api/pull/\(number)", number: number, title: "Layer \(number)",
            author: "mwright", isDraft: false, headRefName: head, baseRefName: base,
            headSha: "h\(number)", baseSha: "b\(number)", size: nil)
    }

    static let three = PRStack(
        layers: [layer(1, head: "a", base: "main"), layer(2, head: "b", base: "a"), layer(3, head: "c", base: "b")],
        currentIndex: 1)

    @Test func positionCountsFromOneAndNamesTheStackSize() {
        #expect(Self.three.position == "Part 2 of 3")
        #expect(Self.three.current.number == 2)
    }

    @Test func layerOffsetWalksUpAndDownAndStopsAtTheEnds() {
        #expect(Self.three.layer(offset: 1)?.number == 3)
        #expect(Self.three.layer(offset: -1)?.number == 1)
        #expect(Self.three.layer(offset: 2) == nil)
        #expect(Self.three.layer(offset: -2) == nil)
    }

    @Test func validBranchNamesPass() {
        for name in ["main", "feature/x-1", "CLM-53522-01-data-layer", "babakks/refresh-token-a-foundation", "v1.2"] {
            #expect(PRStack.isValidBranchName(name), "\(name)")
        }
    }

    @Test func invalidBranchNamesAreRejected() {
        for name in [
            "", "-flag", "a..b", "a@{b", "a.lock", "a/", "a.", "a//b", "a b", "a~b", "a^b", "a:b", "a?b", "a*b",
            "a[b", "a\\b", "a\u{7f}b", "a\nb", "/a", ".a", "a/.b",
        ] {
            #expect(!PRStack.isValidBranchName(name), "\(name)")
        }
    }

    @Test func layersAreIdentifiedByPullRequestNumber() {
        #expect(Self.layer(7, head: "x", base: "main").id == 7)
    }

    @Test func theChainIsCappedAtThirtyTwoLayers() {
        #expect(PRStack.maximumLayers == 32)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PRStackTests`
Expected: compile failure, `cannot find 'StackLayer' in scope`.

- [ ] **Step 3: Write the model**

```swift
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
        for component in name.split(separator: "/", omittingEmptySubsequences: false) {
            if component.hasPrefix(".") { return false }
        }
        let forbidden: Set<Character> = [" ", "~", "^", ":", "?", "*", "[", "\\"]
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7f && !forbidden.contains(Character(scalar))
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PRStackTests`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Contour/Models/PRStack.swift Tests/ContourTests/PRStackTests.swift
git commit -m "Model a stack of pull requests

A stack is an ordered chain of layers, bottom-up, with the opened layer's
index. Branch names are author-controlled and become gh arguments, so the
model carries git's refname rules and a layer whose base fails them is
treated as having no parent.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `StackDiscovery` — parsers, the pure walk, two transports

**Files:**
- Create: `Sources/Contour/Services/StackDiscovery.swift`
- Modify: `Sources/Contour/Services/AnonymousAPISource.swift` (add `pullRequests(owner:repo:query:)` beside `openPullRequests`)
- Create fixtures: `Tests/ContourTests/Fixtures/gh-pr-list-head.json`, `gh-pr-list-base.json`, `rest-pulls-head.json`, `rest-pulls-base.json`
- Modify: `Tests/ContourTests/Fixtures/README.md`
- Test: `Tests/ContourTests/StackDiscoveryParseTests.swift`, `Tests/ContourTests/StackDiscoveryWalkTests.swift`, `Tests/ContourTests/StackDiscoveryFetchTests.swift`

**Interfaces:**
- Consumes: `StackLayer`, `PRStack`, `PRStack.isValidBranchName`, `PRStack.maximumLayers` (Task 1); `Shell.run`, `GitHubAccessMode`, `AnonymousAPISource`, `RawPRContext`.
- Produces:
  - `struct StackDiscovery: Sendable` with `var ghAvailable`, `var runGH`, `var anonymous`, and `func discover(ctx: RawPRContext, access: GitHubAccessMode) async -> PRStack?`.
  - `static func walk(current: StackLayer, parent: (String) async throws -> StackLayer?, children: (String) async throws -> [StackLayer]) async throws -> PRStack?`
  - `static func arguments(repository: String, filter: Filter) -> [String]`, `static func restQuery(owner: String, filter: Filter) -> String`
  - `static func parseGH(_ data: Data) -> [StackLayer]?`, `static func parseREST(_ data: Data, repository: String) -> [StackLayer]?`
  - `static func layer(from ctx: RawPRContext) -> StackLayer`
  - `enum Filter: Equatable, Sendable { case head(String), base(String) }`
  - `AnonymousAPISource.pullRequests(owner:repo:query:) async throws -> Data`

- [ ] **Step 1: Capture the fixtures**

The `cli/cli` repository has a public seven-layer stack (`Refreshable tokens (1/7)` to `(7/7)`, PRs 14450–14456, head branches `babakks/refresh-token-*`). Capture the parent-of and children-of answers for layer 2's base and head:

```bash
cd Tests/ContourTests/Fixtures
gh pr list -R cli/cli --state open --limit 10 --head babakks/refresh-token-a-foundation \
  --json number,url,title,author,isDraft,headRefName,baseRefName,headRefOid,baseRefOid,additions,deletions,changedFiles,isCrossRepository \
  > gh-pr-list-head.json
gh pr list -R cli/cli --state open --limit 10 --base babakks/refresh-token-a-foundation \
  --json number,url,title,author,isDraft,headRefName,baseRefName,headRefOid,baseRefOid,additions,deletions,changedFiles,isCrossRepository \
  > gh-pr-list-base.json
gh api "repos/cli/cli/pulls?state=open&per_page=10&head=cli:babakks/refresh-token-a-foundation" \
  --jq '[.[] | {number, html_url, title, draft, user: {login: .user.login}, head: {ref: .head.ref, sha: .head.sha, repo: {full_name: .head.repo.full_name}}, base: {ref: .base.ref, sha: .base.sha}, additions, deletions, changed_files}]' \
  > rest-pulls-head.json
gh api "repos/cli/cli/pulls?state=open&per_page=10&base=babakks/refresh-token-a-foundation" \
  --jq '[.[] | {number, html_url, title, draft, user: {login: .user.login}, head: {ref: .head.ref, sha: .head.sha, repo: {full_name: .head.repo.full_name}}, base: {ref: .base.ref, sha: .base.sha}, additions, deletions, changed_files}]' \
  > rest-pulls-base.json
```

Check each file: the head fixtures hold exactly one row, PR 14450 with base `trunk`; the base fixtures hold exactly one row, PR 14451 with head `babakks/refresh-token-b-domain`. If the stack has merged since, pick another open stack (search `gh pr list -R cli/cli --search "(1/" --json number,headRefName,baseRefName`) and adjust the numbers in the tests below. The REST rows carry `"additions": null`; keep them, that is the case Review Focus 5 pins.

Append to `Tests/ContourTests/Fixtures/README.md`:

```markdown
## `gh-pr-list-head.json`, `gh-pr-list-base.json`
Real output of `gh pr list -R cli/cli --state open --limit 10 --head babakks/refresh-token-a-foundation --json
number,url,title,author,isDraft,headRefName,baseRefName,headRefOid,baseRefOid,additions,deletions,changedFiles,isCrossRepository`
and the same with `--base` in place of `--head`, captured 2026-10-06 and unedited. The branch is
layer 1 of a seven-layer stack (`Refreshable tokens (1/7)` to `(7/7)`); the `--head` answer is that
layer, the `--base` answer is layer 2. `StackDiscoveryParseTests` relies on each holding one row.

## `rest-pulls-head.json`, `rest-pulls-base.json`
Real output of `GET /repos/cli/cli/pulls?state=open&per_page=10&head=cli:babakks/refresh-token-a-foundation`
and `...&base=babakks/refresh-token-a-foundation`, captured 2026-10-06. Each response was
projected with `jq` to the fields the parser reads (`number`, `title`, `html_url`, `draft`,
`user.login`, `head.ref`, `head.sha`, `head.repo.full_name`, `base.ref`, `base.sha`, `additions`,
`deletions`, `changed_files`). No value was changed. The list endpoint returns `null` for the
three size fields, which is why `StackLayer.size` is optional.
```

- [ ] **Step 2: Write the failing parse tests**

```swift
import Foundation
import Testing

@testable import Contour

struct StackDiscoveryParseTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func theGHHeadFixtureIsTheBottomLayerWithItsSize() throws {
        let layers = try #require(StackDiscovery.parseGH(try fixture("gh-pr-list-head")))
        let layer = try #require(layers.first)
        #expect(layers.count == 1)
        #expect(layer.number == 14450)
        #expect(layer.baseRefName == "trunk")
        #expect(layer.headRefName == "babakks/refresh-token-a-foundation")
        #expect(layer.url == "https://github.com/cli/cli/pull/14450")
        #expect(layer.author == "babakks")
        #expect(layer.headSha.count == 40)
        #expect(layer.baseSha.count == 40)
        #expect((layer.size?.changedFiles ?? 0) > 0)
    }

    @Test func theGHBaseFixtureIsTheLayerAbove() throws {
        let layers = try #require(StackDiscovery.parseGH(try fixture("gh-pr-list-base")))
        #expect(layers.map(\.number) == [14451])
        #expect(layers.first?.baseRefName == "babakks/refresh-token-a-foundation")
    }

    @Test func theRESTFixturesParseWithoutSizes() throws {
        let head = try #require(StackDiscovery.parseREST(try fixture("rest-pulls-head"), repository: "cli/cli"))
        let base = try #require(StackDiscovery.parseREST(try fixture("rest-pulls-base"), repository: "cli/cli"))
        #expect(head.map(\.number) == [14450])
        #expect(base.map(\.number) == [14451])
        #expect(head.first?.size == nil)
        #expect(head.first?.headSha.count == 40)
        #expect(head.first?.author == "babakks")
        #expect(head.first?.url == "https://github.com/cli/cli/pull/14450")
    }

    @Test func aGHRowFromAForkIsIgnored() {
        let json = """
            [{"number":1,"url":"https://github.com/acme/api/pull/1","title":"t","author":{"login":"x"},
              "isDraft":false,"headRefName":"h","baseRefName":"b","headRefOid":"1","baseRefOid":"2",
              "additions":1,"deletions":0,"changedFiles":1,"isCrossRepository":true}]
            """
        #expect(StackDiscovery.parseGH(Data(json.utf8)) == [])
    }

    @Test func aRESTRowFromAnotherRepositoryIsIgnored() {
        let json = """
            [{"number":1,"html_url":"https://github.com/acme/api/pull/1","title":"t","draft":false,
              "user":{"login":"x"},"head":{"ref":"h","sha":"1","repo":{"full_name":"someone/api"}},
              "base":{"ref":"b","sha":"2"},"additions":null,"deletions":null,"changed_files":null}]
            """
        #expect(StackDiscovery.parseREST(Data(json.utf8), repository: "acme/api") == [])
    }

    @Test func rowsMissingRequiredFieldsAreSkippedAndNonArraysAreNil() {
        #expect(StackDiscovery.parseGH(Data("{}".utf8)) == nil)
        #expect(StackDiscovery.parseREST(Data("not json".utf8), repository: "acme/api") == nil)
        #expect(StackDiscovery.parseGH(Data("[{\"number\":3}]".utf8)) == [])
    }

    @Test func aGHRowWithoutSizeFieldsHasNoSize() {
        let json = """
            [{"number":1,"url":"https://github.com/acme/api/pull/1","title":"t","author":{"login":"x"},
              "isDraft":true,"headRefName":"h","baseRefName":"b","headRefOid":"1","baseRefOid":"2",
              "isCrossRepository":false}]
            """
        let layers = StackDiscovery.parseGH(Data(json.utf8))
        #expect(layers?.first?.size == nil)
        #expect(layers?.first?.isDraft == true)
    }
}
```

- [ ] **Step 3: Write the failing walk tests**

```swift
import Foundation
import Testing

@testable import Contour

struct StackDiscoveryWalkTests {
    private struct Lookups: Sendable {
        var byHead: [String: StackLayer] = [:]
        var byBase: [String: [StackLayer]] = [:]
        var parentCalls: [String] = []

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

    @Test func aCycleEndsTheWalk() async throws {
        let a = PRStackTests.layer(1, head: "a", base: "b")
        let b = PRStackTests.layer(2, head: "b", base: "a")
        let stack = try await StackDiscovery.walk(
            current: a, parent: { base in base == "b" ? b : (base == "a" ? a : nil) }, children: { _ in [] })
        #expect(stack?.layers.map(\.number) == [2, 1])
    }

    @Test func theWalkIsCappedAtTheMaximumNumberOfLayers() async throws {
        let names = (1...40).map { "l\($0)" }
        let layers = Self.chain(names)
        let lookups = Self.lookups(layers)
        let stack = try await StackDiscovery.walk(
            current: layers[0], parent: lookups.parent, children: lookups.children)
        #expect(stack?.layers.count == PRStack.maximumLayers)
    }

    @Test func aThrowingLookupPropagates() async {
        struct Boom: Error {}
        let alone = PRStackTests.layer(9, head: "solo", base: "main")
        await #expect(throws: Boom.self) {
            try await StackDiscovery.walk(current: alone, parent: { _ in throw Boom() }, children: { _ in [] })
        }
    }
}
```

- [ ] **Step 4: Write the failing fetch tests**

```swift
import Foundation
import Testing
import os

@testable import Contour

struct StackDiscoveryFetchTests {
    private func context(head: String = "b", base: String = "a") -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/api/pull/2", owner: "acme", repo: "api", number: 2,
            title: "Layer 2", body: "", author: "mwright", state: "OPEN", headRefName: head,
            baseRefName: base, headSha: "h2", baseSha: "b2", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/api.git", additions: 5, deletions: 1, changedFiles: 2,
            files: [], commits: [], comments: [], reviews: [], diff: "")
    }

    private func row(_ number: Int, head: String, base: String) -> String {
        """
        {"number":\(number),"url":"https://github.com/acme/api/pull/\(number)","title":"Layer \(number)",
         "author":{"login":"mwright"},"isDraft":false,"headRefName":"\(head)","baseRefName":"\(base)",
         "headRefOid":"h\(number)","baseRefOid":"b\(number)","additions":1,"deletions":0,"changedFiles":1,
         "isCrossRepository":false}
        """
    }

    @Test func ghArgumentsFilterByHeadOrBase() {
        #expect(
            StackDiscovery.arguments(repository: "acme/api", filter: .head("a")) == [
                "pr", "list", "-R", "acme/api", "--state", "open", "--limit", "10", "--head", "a",
                "--json", StackDiscovery.ghFields,
            ])
        #expect(StackDiscovery.arguments(repository: "acme/api", filter: .base("b")).contains("--base"))
    }

    @Test func restQueryEncodesTheBranchAndPrefixesTheOwnerOnHead() {
        #expect(
            StackDiscovery.restQuery(owner: "acme", filter: .head("feature/x&y"))
                == "state=open&per_page=10&head=acme:feature/x%26y")
        #expect(StackDiscovery.restQuery(owner: "acme", filter: .base("main")) == "state=open&per_page=10&base=main")
    }

    @Test func theOpenedPullRequestBecomesTheCurrentLayer() {
        let layer = StackDiscovery.layer(from: context())
        #expect(layer.number == 2)
        #expect(layer.headRefName == "b")
        #expect(layer.size == StackLayer.Size(additions: 5, deletions: 1, changedFiles: 2))
    }

    @Test func ghDiscoveryWalksBothWaysAndOrdersBottomUp() async {
        let seen = OSAllocatedUnfairLock<[[String]]>(initialState: [])
        let one = row(1, head: "a", base: "main")
        let three = row(3, head: "c", base: "b")
        let service = StackDiscovery(
            ghAvailable: { true },
            runGH: { arguments in
                seen.withLock { $0.append(arguments) }
                if arguments.contains("--head") {
                    return arguments.contains("a") ? "[\(one)]" : "[]"
                }
                return arguments.contains("b") ? "[\(three)]" : "[]"
            })
        let stack = await service.discover(ctx: context(), access: .gh)
        #expect(stack?.layers.map(\.number) == [1, 2, 3])
        #expect(stack?.currentIndex == 1)
        #expect(seen.withLock { $0.count } == 4)
    }

    @Test func aFailingTransportYieldsNoStack() async {
        struct Boom: Error {}
        let service = StackDiscovery(ghAvailable: { true }, runGH: { _ in throw Boom() })
        #expect(await service.discover(ctx: context(), access: .gh) == nil)
    }

    @Test func ghAccessWithoutGHRunsNothing() async {
        let service = StackDiscovery(
            ghAvailable: { false },
            runGH: { _ in
                Issue.record("gh must not run")
                return "[]"
            })
        #expect(await service.discover(ctx: context(), access: .gh) == nil)
    }

    @Test func unparseableOutputYieldsNoStack() async {
        let service = StackDiscovery(ghAvailable: { true }, runGH: { _ in "nope" })
        #expect(await service.discover(ctx: context(), access: .gh) == nil)
    }
}
```

- [ ] **Step 5: Run the three suites to verify they fail**

Run: `swift test --filter StackDiscovery`
Expected: compile failure, `cannot find 'StackDiscovery' in scope`.

- [ ] **Step 6: Add the REST list call to `AnonymousAPISource`**

In `Sources/Contour/Services/AnonymousAPISource.swift`, directly after `openPullRequests(owner:repo:limit:)`:

```swift
    func pullRequests(owner: String, repo: String, query: String) async throws -> Data {
        let (data, _) = try await send(
            request("/repos/\(owner)/\(repo)/pulls?\(query)", accept: "application/vnd.github+json"),
            owner: owner, repo: repo)
        return data
    }
```

- [ ] **Step 7: Write `StackDiscovery`**

```swift
import Foundation
import os

private let stackLogger = Logger(subsystem: "Contour", category: "StackDiscovery")

struct StackDiscovery: Sendable {
    enum Filter: Equatable, Sendable {
        case head(String)
        case base(String)
    }

    var ghAvailable: @Sendable () -> Bool = { Shell.which("gh") != nil }
    var runGH: @Sendable ([String]) async throws -> String = { try await Shell.run("gh", $0) }
    var anonymous = AnonymousAPISource()

    static let ghFields =
        "number,url,title,author,isDraft,headRefName,baseRefName,headRefOid,baseRefOid,"
        + "additions,deletions,changedFiles,isCrossRepository"
    static let pageSize = 10

    func discover(ctx: RawPRContext, access: GitHubAccessMode) async -> PRStack? {
        guard let transport = WatchedPullRequests.transport(access: access, ghAvailable: ghAvailable()) else {
            return nil
        }
        let repository = "\(ctx.owner)/\(ctx.repo)"
        do {
            return try await Self.walk(
                current: Self.layer(from: ctx),
                parent: { base in try await self.list(.head(base), ctx: ctx, transport: transport).first },
                children: { head in try await self.list(.base(head), ctx: ctx, transport: transport) })
        } catch {
            stackLogger.error(
                "Stack discovery for \(repository, privacy: .public) #\(ctx.number) failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private func list(
        _ filter: Filter, ctx: RawPRContext, transport: WatchedPullRequests.Transport
    ) async throws -> [StackLayer] {
        let repository = "\(ctx.owner)/\(ctx.repo)"
        let layers: [StackLayer]?
        switch transport {
        case .gh:
            layers = Self.parseGH(Data(try await runGH(Self.arguments(repository: repository, filter: filter)).utf8))
        case .rest:
            layers = Self.parseREST(
                try await anonymous.pullRequests(
                    owner: ctx.owner, repo: ctx.repo, query: Self.restQuery(owner: ctx.owner, filter: filter)),
                repository: repository)
        }
        guard let layers else { throw GitHubServiceError.malformedResponse("pull request list") }
        return layers
    }

    static func walk(
        current: StackLayer,
        parent: (String) async throws -> StackLayer?,
        children: (String) async throws -> [StackLayer]
    ) async throws -> PRStack? {
        var seen: Set<String> = [current.headRefName]
        var below: [StackLayer] = []
        var cursor = current
        while below.count + 1 < PRStack.maximumLayers, PRStack.isValidBranchName(cursor.baseRefName),
            !seen.contains(cursor.baseRefName), let next = try await parent(cursor.baseRefName)
        {
            seen.insert(next.headRefName)
            below.insert(next, at: 0)
            cursor = next
        }
        var above: [StackLayer] = []
        cursor = current
        while below.count + 1 + above.count < PRStack.maximumLayers, PRStack.isValidBranchName(cursor.headRefName) {
            let candidates = try await children(cursor.headRefName)
            guard candidates.count == 1, let next = candidates.first, !seen.contains(next.headRefName) else { break }
            seen.insert(next.headRefName)
            above.append(next)
            cursor = next
        }
        guard !below.isEmpty || !above.isEmpty else { return nil }
        return PRStack(layers: below + [current] + above, currentIndex: below.count)
    }

    static func layer(from ctx: RawPRContext) -> StackLayer {
        StackLayer(
            url: ctx.url, number: ctx.number, title: ctx.title, author: ctx.author, isDraft: false,
            headRefName: ctx.headRefName, baseRefName: ctx.baseRefName, headSha: ctx.headSha,
            baseSha: ctx.baseSha,
            size: StackLayer.Size(additions: ctx.additions, deletions: ctx.deletions, changedFiles: ctx.changedFiles))
    }

    static func arguments(repository: String, filter: Filter) -> [String] {
        var arguments = ["pr", "list", "-R", repository, "--state", "open", "--limit", String(pageSize)]
        switch filter {
        case .head(let branch): arguments += ["--head", branch]
        case .base(let branch): arguments += ["--base", branch]
        }
        return arguments + ["--json", ghFields]
    }

    static func restQuery(owner: String, filter: Filter) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/~"))
        func encoded(_ branch: String) -> String {
            branch.addingPercentEncoding(withAllowedCharacters: allowed) ?? branch
        }
        switch filter {
        case .head(let branch): return "state=open&per_page=\(pageSize)&head=\(owner):\(encoded(branch))"
        case .base(let branch): return "state=open&per_page=\(pageSize)&base=\(encoded(branch))"
        }
    }

    static func parseGH(_ data: Data) -> [StackLayer]? {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard (row["isCrossRepository"] as? Bool) != true,
                let url = row["url"] as? String, let number = row["number"] as? Int,
                let title = row["title"] as? String,
                let head = row["headRefName"] as? String, let base = row["baseRefName"] as? String,
                let headSha = row["headRefOid"] as? String, let baseSha = row["baseRefOid"] as? String
            else { return nil }
            return StackLayer(
                url: url, number: number, title: title,
                author: ((row["author"] as? [String: Any])?["login"] as? String) ?? "unknown",
                isDraft: (row["isDraft"] as? Bool) ?? false,
                headRefName: head, baseRefName: base, headSha: headSha, baseSha: baseSha,
                size: size(additions: row["additions"], deletions: row["deletions"], files: row["changedFiles"]))
        }
    }

    static func parseREST(_ data: Data, repository: String) -> [StackLayer]? {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let url = row["html_url"] as? String, let number = row["number"] as? Int,
                let title = row["title"] as? String,
                let head = row["head"] as? [String: Any], let base = row["base"] as? [String: Any],
                let headRef = head["ref"] as? String, let baseRef = base["ref"] as? String,
                let headSha = head["sha"] as? String, let baseSha = base["sha"] as? String,
                ((head["repo"] as? [String: Any])?["full_name"] as? String) == repository
            else { return nil }
            return StackLayer(
                url: url, number: number, title: title,
                author: ((row["user"] as? [String: Any])?["login"] as? String) ?? "unknown",
                isDraft: (row["draft"] as? Bool) ?? false,
                headRefName: headRef, baseRefName: baseRef, headSha: headSha, baseSha: baseSha,
                size: size(additions: row["additions"], deletions: row["deletions"], files: row["changed_files"]))
        }
    }

    private static func size(additions: Any?, deletions: Any?, files: Any?) -> StackLayer.Size? {
        guard let additions = additions as? Int, let deletions = deletions as? Int, let files = files as? Int else {
            return nil
        }
        return StackLayer.Size(additions: additions, deletions: deletions, changedFiles: files)
    }
}
```

`WatchedPullRequests.transport` and `WatchedPullRequests.Transport` already exist and are reused; do not duplicate them.

- [ ] **Step 8: Run the three suites to verify they pass**

Run: `swift test --filter StackDiscovery`
Expected: all tests PASS. If `theGHHeadFixtureIsTheBottomLayerWithItsSize` fails on the fixture, re-check Step 1's capture.

- [ ] **Step 9: Commit**

```bash
git add Sources/Contour/Services/StackDiscovery.swift Sources/Contour/Services/AnonymousAPISource.swift \
  Tests/ContourTests/Fixtures/gh-pr-list-head.json Tests/ContourTests/Fixtures/gh-pr-list-base.json \
  Tests/ContourTests/Fixtures/rest-pulls-head.json Tests/ContourTests/Fixtures/rest-pulls-base.json \
  Tests/ContourTests/Fixtures/README.md Tests/ContourTests/StackDiscoveryParseTests.swift \
  Tests/ContourTests/StackDiscoveryWalkTests.swift Tests/ContourTests/StackDiscoveryFetchTests.swift
git commit -m "Discover a pull request's stack by walking branch chains

The parent of a layer is the open pull request whose head is this one's
base; the children are the open pull requests whose base is this one's
head. The walk descends until nothing matches, climbs while exactly one
child matches, stops on a repeated branch and at 32 layers. Both
transports list by head or base with one call per link; the description's
own 'Part 1 of 7' text is never parsed. Rows from forks are dropped so the
chain stays in one repository.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: The stack block in the context file

**Files:**
- Modify: `Sources/Contour/Pipeline/PromptBuilder.swift:2-9`
- Test: `Tests/ContourTests/PromptBuilderTests.swift`

**Interfaces:**
- Consumes: `PRStack`, `StackLayer` (Task 1).
- Produces: `PromptBuilder.contextFileContents(_ ctx: RawPRContext, stack: PRStack? = nil) -> String`, `PromptBuilder.stackBlock(_ stack: PRStack) -> String`.

- [ ] **Step 1: Write the failing tests**

Add to `PromptBuilderTests` (the suite already has a `context(...)` helper building a `RawPRContext`):

```swift
    private func stack() -> PRStack {
        PRStack(
            layers: [
                PRStackTests.layer(1, head: "a", base: "main"),
                PRStackTests.layer(2, head: "b", base: "a"),
                PRStackTests.layer(3, head: "c", base: "b"),
                PRStackTests.layer(4, head: "d", base: "c"),
            ],
            currentIndex: 2)
    }

    @Test func contextFileWithoutAStackIsUnchanged() {
        #expect(PromptBuilder.contextFileContents(context()) == PromptBuilder.contextFileContents(context(), stack: nil))
        #expect(!PromptBuilder.contextFileContents(context()).contains("Stack:"))
    }

    @Test func stackBlockNamesThePositionAndWhichLayersAreInTheCheckout() {
        let block = PromptBuilder.stackBlock(stack())
        #expect(block.hasPrefix("Stack: this pull request is part 3 of 4."))
        #expect(block.contains("Layers 1-2 are already merged into this checkout"))
        #expect(block.contains("Layers 4-4 build on this one and are not in the checkout."))
        #expect(block.contains("<UNTRUSTED_PR_CONTENT>\n1. #1 Layer 1\n2. #2 Layer 2\n3. #3 Layer 3   (this PR)\n4. #4 Layer 4\n</UNTRUSTED_PR_CONTENT>\n"))
    }

    @Test func stackBlockAtTheBottomOmitsTheLowerSentence() {
        var stack = stack()
        stack.currentIndex = 0
        let block = PromptBuilder.stackBlock(stack)
        #expect(!block.contains("already merged into this checkout"))
        #expect(block.contains("Layers 2-4 build on this one"))
    }

    @Test func stackBlockAtTheTopOmitsTheUpperSentence() {
        var stack = stack()
        stack.currentIndex = 3
        let block = PromptBuilder.stackBlock(stack)
        #expect(block.contains("Layers 1-3 are already merged into this checkout"))
        #expect(!block.contains("build on this one"))
    }

    @Test func contextFilePutsTheStackBlockBetweenBaseAndChangedFiles() {
        let text = PromptBuilder.contextFileContents(context(), stack: stack())
        let base = try! #require(text.range(of: "Base: "))
        let stackRange = try! #require(text.range(of: "Stack: this pull request"))
        let files = try! #require(text.range(of: "Changed files ("))
        #expect(base.lowerBound < stackRange.lowerBound)
        #expect(stackRange.lowerBound < files.lowerBound)
    }
```

Use `throws` on the last test instead of `try!` if the suite's style prefers it; the existing tests there are non-throwing, so mark that one `@Test func ... () throws` and use `try #require`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PromptBuilderTests`
Expected: compile failure on `stackBlock` and the `stack:` label.

- [ ] **Step 3: Implement the block**

Replace the signature and the first lines of `contextFileContents`:

```swift
    static func contextFileContents(_ ctx: RawPRContext, stack: PRStack? = nil) -> String {
        var out = "# PR Context (untrusted author content is delimited below)\n\n"
        out += "Repo: \(ctx.owner)/\(ctx.repo)\n"
        out += "PR #\(ctx.number), state \(ctx.state)\n"
        out += "Head: \(ctx.headRefName) @ \(ctx.headSha)\n"
        out += "Base: \(ctx.baseRefName) @ \(ctx.baseSha)\n"
        if let stack { out += stackBlock(stack) }
        out += "Changed files (\(ctx.files.count)): \(ctx.files.joined(separator: ", "))\n\n"
```

and add, after `contextFileName`:

```swift
    static func stackBlock(_ stack: PRStack) -> String {
        let position = stack.currentIndex + 1
        let count = stack.layers.count
        var out = "Stack: this pull request is part \(position) of \(count). Layers are listed bottom-up; each "
        out += "targets the branch of the one before it. "
        if position > 1 {
            out += "Layers 1-\(position - 1) are already merged into this checkout and are not part of this "
            out += "change: treat their code as existing code. "
        }
        if position < count {
            out += "Layers \(position + 1)-\(count) build on this one and are not in the checkout. "
        }
        out += "Review only this layer's diff; code that this layer adds but nothing yet calls is expected "
        out += "when a later layer is the caller.\n<UNTRUSTED_PR_CONTENT>\n"
        for (index, layer) in stack.layers.enumerated() {
            out += "\(index + 1). #\(layer.number) \(layer.title)"
            out += index == stack.currentIndex ? "   (this PR)\n" : "\n"
        }
        out += "</UNTRUSTED_PR_CONTENT>\n"
        return out
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PromptBuilderTests`
Expected: PASS, including the pre-existing tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Contour/Pipeline/PromptBuilder.swift Tests/ContourTests/PromptBuilderTests.swift
git commit -m "Tell the model where a stacked pull request sits

Every stage reads the context file, so one block after the Base line
gives all of them the layer's position, which layers are already in the
checkout and which are not, and that code nothing calls yet is expected
when a later layer is the caller. Titles are author content and sit inside
the untrusted wrapper. A plain pull request's file is byte-identical to
before, so the pipeline version stays at 17.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Discovery in the pipeline, with a grace period

**Files:**
- Modify: `Sources/Contour/Pipeline/AnalysisPipeline.swift` (events enum, init, `run`, new `discoverStack`, `awaitStack`)
- Test: `Tests/ContourTests/AnalysisPipelineTests.swift`

**Interfaces:**
- Consumes: `StackDiscovery.discover(ctx:access:)` (Task 2), `PromptBuilder.contextFileContents(_:stack:)` (Task 3), `AnalysisCache.load(...)`.
- Produces: `PipelineEvent.stack(PRStack, cached: Set<Int>)`; `AnalysisPipeline.init(..., stackDiscoveryOverride: (@Sendable (RawPRContext) async -> PRStack?)? = nil, stackDiscoveryGrace: Duration = .seconds(5))`; `AnalysisPipeline.cachedLayers(of:) -> Set<Int>`.

- [ ] **Step 1: Write the failing tests**

Add to `AnalysisPipelineTests`:

```swift
    private func stack(for ctx: RawPRContext) -> PRStack {
        let current = StackDiscovery.layer(from: ctx)
        let above = StackLayer(
            url: "https://github.com/acme/shop/pull/502", number: 502, title: "Layer 2", author: "someone",
            isDraft: false, headRefName: "fix-2", baseRefName: "fix", headSha: "head2", baseSha: "head1", size: nil)
        return PRStack(layers: [current, above], currentIndex: 0)
    }

    private func stackPipeline(
        ctx: RawPRContext, cache: AnalysisCache, grace: Duration = .seconds(5),
        discover: @escaping @Sendable (RawPRContext) async -> PRStack?
    ) -> AnalysisPipeline {
        AnalysisPipeline(
            harnessID: .claude, trackerID: .none, cache: cache,
            prSourceOverride: FakePRSource(context: ctx),
            checkoutOverride: { try Self.makeCheckout(for: $0) },
            mockOverride: .init(),
            stackDiscoveryOverride: discover,
            stackDiscoveryGrace: grace)
    }

    private func contextFile(_ events: [PipelineEvent]) throws -> String {
        var checkout: RepoCheckout?
        for case .checkout(let c) in events { checkout = c }
        let root = try #require(checkout).rootDir
        return try String(contentsOf: root.appendingPathComponent(PromptBuilder.contextFileName), encoding: .utf8)
    }

    private func stackEvent(_ events: [PipelineEvent]) -> (PRStack, Set<Int>)? {
        for case .stack(let stack, let cached) in events { return (stack, cached) }
        return nil
    }

    @Test func aDiscoveredStackIsEmittedAndWrittenIntoTheContextFile() async throws {
        let ctx = context()
        let stack = stack(for: ctx)
        let pipeline = stackPipeline(ctx: ctx, cache: tempCache()) { _ in stack }
        await pipeline.start(prURL: ctx.url)
        let events = await drain(pipeline)
        #expect(stackEvent(events)?.0 == stack)
        #expect(stackEvent(events)?.1 == [])
        #expect(try contextFile(events).contains("Stack: this pull request is part 1 of 2."))
    }

    @Test func noStackMeansNoEventAndAnUnchangedContextFile() async throws {
        let ctx = context()
        let pipeline = stackPipeline(ctx: ctx, cache: tempCache()) { _ in nil }
        await pipeline.start(prURL: ctx.url)
        let events = await drain(pipeline)
        #expect(stackEvent(events) == nil)
        #expect(!(try contextFile(events).contains("Stack:")))
    }

    @Test func slowDiscoveryDoesNotDelayTheAnalysisButStillArrives() async throws {
        let ctx = context()
        let stack = stack(for: ctx)
        let pipeline = stackPipeline(ctx: ctx, cache: tempCache(), grace: .milliseconds(20)) { _ in
            try? await Task.sleep(for: .milliseconds(400))
            return stack
        }
        await pipeline.start(prURL: ctx.url)
        var events: [PipelineEvent] = []
        var sawComplete = false
        for await event in pipeline.events {
            events.append(event)
            if case .complete = event { sawComplete = true }
            if sawComplete, stackEvent(events) != nil { break }
        }
        #expect(sawComplete)
        #expect(stackEvent(events)?.0 == stack)
        #expect(!(try contextFile(events).contains("Stack:")))
    }

    @Test func layersWithACompleteCachedAnalysisAreReportedAsCached() async throws {
        let ctx = context()
        let cache = tempCache()
        let stack = stack(for: ctx)
        var graph = PRGraph.shell(from: ctx)
        graph.pr.number = 502
        cache.save(
            owner: "acme", repo: "shop", number: 502, headSha: "head2", baseSha: "head1",
            pipelineVersion: AnalysisPipeline.pipelineVersion, graph: graph, diff: "",
            completedStages: Set(PipelineStage.analysis))
        let pipeline = stackPipeline(ctx: ctx, cache: cache) { _ in stack }
        await pipeline.start(prURL: ctx.url)
        let events = await drain(pipeline)
        #expect(stackEvent(events)?.1 == [502])
    }
```

`.complete` from the mock harness comes quickly, well before the 400 ms discovery, so the third test exercises the grace path. If `drain` returns before `.stack` in the first test on a slow machine, that is a bug in the implementation, not the test: with an immediate discovery the stack must be awaited before the context file is written and therefore before any stage runs.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AnalysisPipelineTests`
Expected: compile failure on `stackDiscoveryOverride`.

- [ ] **Step 3: Implement**

In `PipelineEvent`, add after `.checkout(RepoCheckout)`:

```swift
    case stack(PRStack, cached: Set<Int>)
```

In `AnalysisPipeline`, add stored properties beside `mockOverride`:

```swift
    private let stackDiscoveryOverride: (@Sendable (RawPRContext) async -> PRStack?)?
    private let stackDiscoveryGrace: Duration
    private var stack: PRStack?
    private var discoveryFinished = false
    private var discoveryTask: Task<Void, Never>?
```

Extend `init` with two trailing parameters and assignments:

```swift
        mockOverride: AnalysisService.MockOptions? = nil,
        stackDiscoveryOverride: (@Sendable (RawPRContext) async -> PRStack?)? = nil,
        stackDiscoveryGrace: Duration = .seconds(5)
    ) {
        ...
        self.stackDiscoveryOverride = stackDiscoveryOverride
        self.stackDiscoveryGrace = stackDiscoveryGrace
```

In `run(prURL:forceRefresh:)`, right after `setStatus(.fetching, .done)`:

```swift
            discoveryFinished = false
            discoveryTask = Task { await self.discoverStack(ctx) }
```

and replace the context-file write with:

```swift
            let contextFile = checkout.rootDir.appendingPathComponent(PromptBuilder.contextFileName)
            let stack = await awaitStack(grace: stackDiscoveryGrace)
            try PromptBuilder.contextFileContents(ctx, stack: stack).write(
                to: contextFile, atomically: true, encoding: .utf8)
```

Add the helpers near `lookUpTicket`:

```swift
    private func discoverStack(_ ctx: RawPRContext) async {
        defer { discoveryFinished = true }
        let found: PRStack?
        if let stackDiscoveryOverride {
            found = await stackDiscoveryOverride(ctx)
        } else {
            found = await StackDiscovery().discover(ctx: ctx, access: github.mode)
        }
        guard let found, !Task.isCancelled else { return }
        stack = found
        log(.fetching, "part \(found.currentIndex + 1) of a \(found.layers.count)-layer stack")
        continuation.yield(.stack(found, cached: cachedLayers(of: found)))
    }

    private func awaitStack(grace: Duration) async -> PRStack? {
        let deadline = ContinuousClock.now + grace
        while !discoveryFinished, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return stack
    }

    func cachedLayers(of stack: PRStack) -> Set<Int> {
        guard let ctx else { return [] }
        return Set(
            stack.layers.filter { layer in
                layer.number != ctx.number
                    && cache.load(
                        owner: ctx.owner, repo: ctx.repo, number: layer.number, headSha: layer.headSha,
                        baseSha: layer.baseSha, pipelineVersion: Self.pipelineVersion
                    )?.completedStages.isSuperset(of: PipelineStage.analysis) == true
            }.map(\.number))
    }

```

The poll runs on the actor, so a discovery that finishes sets `discoveryFinished` between two sleeps and the loop exits within 20 ms. `runOffline` keeps writing the file without a stack; integration and benchmark runs do not discover.

Add `discoveryTask?.cancel()` to `cancelInFlight()` so a closed review does not emit later; `discoverStack` checks `Task.isCancelled` before emitting.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AnalysisPipelineTests`
Expected: PASS. Then `swift build` to confirm no Swift 6 isolation warnings; `Task { await self.discoverStack(ctx) }` inside the actor inherits actor isolation.

- [ ] **Step 5: Commit**

```bash
git add Sources/Contour/Pipeline/AnalysisPipeline.swift Tests/ContourTests/AnalysisPipelineTests.swift
git commit -m "Discover the stack beside the checkout and feed it to the prompt

Discovery starts as soon as the pull request is fetched and usually lands
before the checkout does. The context file waits for it up to five seconds
past the checkout, then is written without the block so a slow GitHub
never delays the first stage; the stack event still arrives and the strip
still appears. Layers with a complete cache entry for their current head
and base are reported with the event so the strip can mark them.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Stack state and layer navigation in `GraphStore`

**Files:**
- Modify: `Sources/Contour/Services/GraphStore.swift` (state, `load` reset, `handle`, four members)
- Test: `Tests/ContourTests/GraphStoreStackTests.swift`

**Interfaces:**
- Consumes: `PipelineEvent.stack` (Task 4), `PRStack.layer(offset:)` (Task 1).
- Produces: `GraphStore.stack: PRStack?`, `GraphStore.stackAnalysis: [Int: StackLayerStatus]`, `enum StackLayerStatus: Equatable { case cached }`, `openLayer(_:)`, `openNextLayer()`, `openPreviousLayer()`, `canOpenNextLayer`, `canOpenPreviousLayer`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import Contour

@MainActor
@Suite(.serialized)
struct GraphStoreStackTests {
    private struct FakePRSource: PRSource {
        let describesItself = "fake (tests)"
        let context: RawPRContext
        func fetchContext(prURL: String) async throws -> RawPRContext { context }
        func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? { nil }
    }

    private func context(number: Int) -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/shop/pull/\(number)", owner: "acme", repo: "shop", number: number,
            title: "Layer \(number)", body: "", author: "someone", state: "OPEN", headRefName: "l\(number)",
            baseRefName: number == 1 ? "main" : "l\(number - 1)", headSha: "head\(number)", baseSha: "base\(number)",
            isCrossRepository: false, headCloneURL: "https://github.com/acme/shop.git", additions: 1, deletions: 0,
            changedFiles: 1, files: ["a.rs"], commits: [], comments: [], reviews: [], diff: "diff")
    }

    private func stack(current: Int) -> PRStack {
        PRStack(
            layers: (1...3).map { StackDiscovery.layer(from: context(number: $0)) },
            currentIndex: current - 1)
    }

    private func preferences() -> Preferences {
        let defaults = UserDefaults(suiteName: "contour-stack-\(UUID().uuidString)")!
        return Preferences(defaults: defaults, environment: ["CONTOUR_HARNESS": "claude", "CONTOUR_TRACKER": "none"])
    }

    private func makeStore(discover: @escaping @Sendable (RawPRContext) async -> PRStack?) -> GraphStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "contour-stack-\(UUID().uuidString)", isDirectory: true)
        return GraphStore(
            preferences: preferences(),
            makePipeline: { harness, tracker, _ in
                AnalysisPipeline(
                    harnessID: harness, trackerID: tracker, cache: AnalysisCache(directory: directory),
                    prSourceOverride: FakePRSource(context: self.context(number: 2)),
                    checkoutOverride: { fetched in
                        let dir = FileManager.default.temporaryDirectory
                            .appendingPathComponent("contour-checkout-\(UUID().uuidString)", isDirectory: true)
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        return RepoCheckout(rootDir: dir, headSha: fetched.headSha, baseSha: fetched.baseSha)
                    },
                    mockOverride: AnalysisService.MockOptions(latencyScale: 0.05),
                    stackDiscoveryOverride: discover)
            },
            metricsURL: directory.appendingPathComponent("metrics.jsonl"),
            submitReview: { _, _, _ in },
            canUseGitHubCLI: true)
    }

    private func wait(until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    @Test func theStackArrivesWithTheReviewAndNamesNeighbours() async {
        let stack = stack(current: 2)
        let store = makeStore { _ in stack }
        store.load(prURL: context(number: 2).url)
        #expect(await wait { store.stack != nil })
        #expect(store.stack == stack)
        #expect(store.canOpenNextLayer)
        #expect(store.canOpenPreviousLayer)
        #expect(store.stackAnalysis.isEmpty)
    }

    @Test func openingTheNextLayerLoadsItsURLAndClearsTheOldStack() async {
        let stack = stack(current: 2)
        let store = makeStore { _ in stack }
        store.load(prURL: context(number: 2).url)
        #expect(await wait { store.stack != nil })
        store.openNextLayer()
        #expect(store.lastPRURL == context(number: 3).url)
        #expect(store.stack == nil)
    }

    @Test func atTheEndsNextAndPreviousAreDisabledAndDoNothing() async {
        let store = makeStore { _ in self.stack(current: 3) }
        store.load(prURL: context(number: 2).url)
        #expect(await wait { store.stack != nil })
        #expect(!store.canOpenNextLayer)
        store.openNextLayer()
        #expect(store.lastPRURL == context(number: 2).url)
    }

    @Test func withoutAStackNothingIsEnabled() {
        let store = makeStore { _ in nil }
        #expect(!store.canOpenNextLayer)
        #expect(!store.canOpenPreviousLayer)
        store.openPreviousLayer()
        #expect(store.lastPRURL == nil)
    }

    @Test func cachedLayersFromTheEventAreMarked() async {
        let stack = stack(current: 1)
        let store = makeStore { _ in stack }
        store.load(prURL: context(number: 2).url)
        #expect(await wait { store.stack != nil })
        store.handle(.stack(stack, cached: [3]))
        #expect(store.stackAnalysis == [3: .cached])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter GraphStoreStackTests`
Expected: compile failure on `store.stack`.

- [ ] **Step 3: Implement**

In `GraphStore.swift`, add beside `SessionPhase`:

```swift
enum StackLayerStatus: Equatable {
    case cached
}
```

Add stored state after `private(set) var metrics`:

```swift
    private(set) var stack: PRStack?
    private(set) var stackAnalysis: [Int: StackLayerStatus] = [:]
```

In `load(prURL:forceRefresh:)`, after `diagramMode = .delta`:

```swift
        stack = nil
        stackAnalysis = [:]
```

In `handle(_:)`, add a case after `.checkout`:

```swift
        case .stack(let found, let cached):
            stack = found
            stackAnalysis = Dictionary(uniqueKeysWithValues: cached.map { ($0, StackLayerStatus.cached) })
```

Add the actions after `reopen()`:

```swift
    var canOpenNextLayer: Bool { stack?.layer(offset: 1) != nil }
    var canOpenPreviousLayer: Bool { stack?.layer(offset: -1) != nil }

    @MainActor
    func openLayer(_ layer: StackLayer) {
        noteEngagement()
        load(prURL: layer.url)
    }

    @MainActor
    func openNextLayer() {
        guard let next = stack?.layer(offset: 1) else { return }
        openLayer(next)
    }

    @MainActor
    func openPreviousLayer() {
        guard let previous = stack?.layer(offset: -1) else { return }
        openLayer(previous)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter GraphStoreStackTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Contour/Services/GraphStore.swift Tests/ContourTests/GraphStoreStackTests.swift
git commit -m "Keep the stack as session state and move between its layers

The stack is rediscovered on every open so it reflects merges since the
last visit, and opening another layer is an ordinary load of that layer's
URL: the current review closes, the next opens, and a layer analysed
earlier is a cache hit.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: The stack strip in the Overview header

**Files:**
- Create: `Sources/Contour/Views/Summary/StackStrip.swift`
- Modify: `Sources/Contour/Views/Summary/SummaryView.swift` (three properties, the header)
- Modify: `Sources/Contour/Views/ContentView.swift:526-529` (pass the stack through)
- Test: `Tests/ContourTests/StackStripTests.swift`, additions to `Tests/ContourTests/SummaryViewRenderTests.swift`

**Interfaces:**
- Consumes: `PRStack`, `StackLayer`, `StackLayerStatus`, `GraphStore.stack`, `GraphStore.stackAnalysis`, `GraphStore.openLayer(_:)`.
- Produces: `StackStrip` view; `enum StackStripLogic` with `positionText(_:)`, `chipLabel(index:layer:)`, `tooltip(_:)`, `statusSymbol(_:)`; `SummaryView.stack`, `SummaryView.stackStatuses`, `SummaryView.openLayer`.

- [ ] **Step 1: Write the failing logic and render tests**

```swift
import SwiftUI
import Testing

@testable import Contour

struct StackStripTests {
    private let stack = PRStackTests.three

    @Test func positionTextSaysWhereTheLayerSits() {
        #expect(StackStripLogic.positionText(stack) == "Part 2 of 3 in a stack")
    }

    @Test func chipLabelLeadsWithTheOneBasedIndex() {
        #expect(StackStripLogic.chipLabel(index: 0, layer: stack.layers[0]) == "1 · Layer 1")
    }

    @Test func tooltipNamesTitleAuthorAndSizeWhenKnown() {
        var layer = stack.layers[2]
        layer.size = StackLayer.Size(additions: 120, deletions: 7, changedFiles: 9)
        #expect(StackStripLogic.tooltip(layer) == "#3 Layer 3\nmwright · +120 −7 · 9 files")
        #expect(StackStripLogic.tooltip(stack.layers[0]) == "#1 Layer 1\nmwright")
    }

    @Test func tooltipUsesSingularForOneFile() {
        var layer = stack.layers[0]
        layer.size = StackLayer.Size(additions: 1, deletions: 0, changedFiles: 1)
        #expect(StackStripLogic.tooltip(layer).hasSuffix("1 file"))
    }

    @Test func statusSymbolMarksCachedLayersOnly() {
        #expect(StackStripLogic.statusSymbol(.cached) == "checkmark.circle.fill")
        #expect(StackStripLogic.statusSymbol(nil) == nil)
    }

    @MainActor
    @Test func theStripRendersWithAndWithoutStatuses() {
        let view = StackStrip(stack: stack, statuses: [1: .cached], openLayer: { _ in })
        let renderer = ImageRenderer(content: view.frame(width: 900, height: 80))
        renderer.scale = 1
        #expect(renderer.nsImage != nil)
        let bare = ImageRenderer(content: StackStrip(stack: stack, statuses: [:], openLayer: { _ in }).frame(width: 400))
        #expect(bare.nsImage != nil)
    }

    @MainActor
    @Test func pressingAChipOpensThatLayer() {
        var opened: [Int] = []
        let strip = StackStrip(stack: stack, statuses: [:], openLayer: { opened.append($0.number) })
        let hosting = NSHostingView(rootView: strip)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 80)
        let window = HeadlessWindow(size: hosting.frame.size)
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        func walk(_ node: Any) {
            guard let object = node as? NSObject else { return }
            let role = object.perform(NSSelectorFromString("accessibilityRole"))?.takeUnretainedValue() as? String
            if role == NSAccessibility.Role.button.rawValue {
                _ = object.perform(NSSelectorFromString("accessibilityPerformPress"))
            }
            let children = object.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue()
            for child in children as? [Any] ?? [] { walk(child) }
        }
        walk(hosting)
        window.orderOut(nil)
        #expect(Set(opened) == [1, 2, 3])
    }
}
```

Add to `SummaryViewRenderTests`:

```swift
    @Test func rendersTheStackStripInTheHeader() {
        let view = SummaryView(
            graph: ContourSampleData.publishTriggeredReindex, analysis: AnalysisState(isComplete: true),
            discussed: [], onRetry: { _ in }, navigate: { _ in },
            stack: PRStackTests.three, stackStatuses: [3: .cached], openLayer: { _ in })
        #expect(render(view) != nil)
    }
```

`HeadlessWindow` already exists in `Tests/ContourTests/HeadlessWindow.swift`. `PRStackTests.three` and `PRStackTests.layer` are the Task 1 fixtures, which is why they are `static` and internal.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter StackStripTests`
Expected: compile failure on `StackStripLogic`.

- [ ] **Step 3: Write the strip**

```swift
import SwiftUI

enum StackStripLogic {
    static func positionText(_ stack: PRStack) -> String { "\(stack.position) in a stack" }

    static func chipLabel(index: Int, layer: StackLayer) -> String { "\(index + 1) · \(layer.title)" }

    static func tooltip(_ layer: StackLayer) -> String {
        var line = layer.author
        if let size = layer.size {
            let files = size.changedFiles == 1 ? "1 file" : "\(size.changedFiles) files"
            line += " · +\(size.additions) \u{2212}\(size.deletions) · \(files)"
        }
        return "#\(layer.number) \(layer.title)\n\(line)"
    }

    static func statusSymbol(_ status: StackLayerStatus?) -> String? {
        switch status {
        case .cached: return "checkmark.circle.fill"
        case nil: return nil
        }
    }
}

struct StackStrip: View {
    let stack: PRStack
    let statuses: [Int: StackLayerStatus]
    let openLayer: (StackLayer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(StackStripLogic.positionText(stack))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(stack.layers.enumerated()), id: \.element.id) { index, layer in
                        chip(index: index, layer: layer)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(index: Int, layer: StackLayer) -> some View {
        let isCurrent = index == stack.currentIndex
        return Button(action: { openLayer(layer) }) {
            HStack(spacing: 4) {
                Text(verbatim: StackStripLogic.chipLabel(index: index, layer: layer))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220)
                if let symbol = StackStripLogic.statusSymbol(statuses[layer.number]) {
                    Image(systemName: symbol).font(.caption2)
                }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.accentColor.opacity(0.18) : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .help(StackStripLogic.tooltip(layer))
        .accessibilityLabel(Text(verbatim: StackStripLogic.chipLabel(index: index, layer: layer)))
    }
}
```

`.disabled(isCurrent)` means the current chip's press does nothing; the press test therefore expects all three numbers only if the disabled button still reports a press through accessibility. If `Set(opened)` comes back as `[1, 3]`, change the test's expectation to `[1, 3]` — the current layer is already open and must not reload.

- [ ] **Step 4: Wire the strip into `SummaryView`**

Add three properties after `var navigate: (NavigationTarget) -> Void`:

```swift
    var stack: PRStack? = nil
    var stackStatuses: [Int: StackLayerStatus] = [:]
    var openLayer: (StackLayer) -> Void = { _ in }
```

In `header`, between the metadata `HStack` and `factsLine`:

```swift
            if let stack {
                StackStrip(stack: stack, statuses: stackStatuses, openLayer: openLayer)
                    .padding(.vertical, 4)
                    .transition(.opacity)
            }
```

In `ContentView.swift` where `SummaryView` is built (around line 526):

```swift
            SummaryView(
                graph: graph, analysis: analysis, discussed: store.conversations.discussedConsiderationIds,
                onRetry: actions.retry, navigate: actions.navigate,
                stack: store.stack, stackStatuses: store.stackAnalysis, openLayer: actions.openLayer
            )
```

and add to `ContentViewActions`:

```swift
    func openLayer(_ layer: StackLayer) { store.openLayer(layer) }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "StackStripTests|SummaryViewRenderTests|ContentViewActionsTests"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Contour/Views/Summary/StackStrip.swift Sources/Contour/Views/Summary/SummaryView.swift \
  Sources/Contour/Views/ContentView.swift Sources/Contour/Views/ContentViewActions.swift \
  Tests/ContourTests/StackStripTests.swift Tests/ContourTests/SummaryViewRenderTests.swift
git commit -m "Show the stack in the Overview header

One line under the metadata: the layer's position and a chip per layer,
the opened one filled, cached ones ticked, each a button that opens that
layer. The strip appears only for a stacked pull request, and lands with a
fade since discovery usually finishes before anything below it has content.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Next and previous layer in the File menu and ⌘K

**Files:**
- Modify: `Sources/Contour/Views/PRSessionCommands.swift` (actions struct, logic, menu, menu actions)
- Modify: `Sources/Contour/Views/ContentView.swift:92-104` (`sessionActions`)
- Modify: `Sources/Contour/Views/CommandPaletteView.swift` (`allCommands`)
- Test: `Tests/ContourTests/PRSessionCommandsTests.swift`, `Tests/ContourTests/CommandPaletteViewTests.swift`

**Interfaces:**
- Consumes: `GraphStore.canOpenNextLayer`, `canOpenPreviousLayer`, `openNextLayer()`, `openPreviousLayer()` (Task 5).
- Produces: `PRSessionActions.canOpenNextLayer`, `canOpenPreviousLayer`, `openNextLayer`, `openPreviousLayer`; `PRSessionCommandsLogic.nextLayerEnabled(_:)`, `previousLayerEnabled(_:)`; palette titles "Open next layer in stack" and "Open previous layer in stack".

- [ ] **Step 1: Write the failing tests**

Add to `PRSessionCommandsTests`:

```swift
    @Test func layerCommandsAreEnabledOnlyWhenTheSessionSaysSo() {
        let both = PRSessionActions(
            hasOpenPR: true, pullRequestURL: nil, openDifferent: {}, close: {},
            canOpenNextLayer: true, canOpenPreviousLayer: true)
        let none = PRSessionActions(hasOpenPR: true, pullRequestURL: nil, openDifferent: {}, close: {})
        #expect(PRSessionCommandsLogic.nextLayerEnabled(both))
        #expect(PRSessionCommandsLogic.previousLayerEnabled(both))
        #expect(!PRSessionCommandsLogic.nextLayerEnabled(none))
        #expect(!PRSessionCommandsLogic.previousLayerEnabled(none))
        #expect(!PRSessionCommandsLogic.nextLayerEnabled(nil))
    }

    @MainActor
    @Test func menuActionsForwardLayerNavigationToTheSession() {
        var calls: [String] = []
        let session = PRSessionActions(
            hasOpenPR: true, pullRequestURL: nil, openDifferent: {}, close: {},
            openNextLayer: { calls.append("next") }, openPreviousLayer: { calls.append("previous") })
        let actions = PRSessionMenuActions(session: session)
        actions.openNextLayer()
        actions.openPreviousLayer()
        #expect(calls == ["next", "previous"])
    }
```

Add to `CommandPaletteViewTests`:

```swift
    @MainActor
    @Test func layerCommandsAppearOnlyWhenAStackHasANeighbour() {
        let titles = CommandPaletteView.allCommands(store: GraphStore()).map(\.title)
        #expect(!titles.contains("Open next layer in stack"))
        #expect(!titles.contains("Open previous layer in stack"))
    }
```

A positive palette case is covered by `GraphStoreStackTests` plus the pure `canOpenNextLayer` flags; the palette builder reads only those two flags.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "PRSessionCommandsTests|CommandPaletteViewTests"`
Expected: compile failure on `canOpenNextLayer:`.

- [ ] **Step 3: Implement**

In `PRSessionActions`, add after `var toggleWatch: () -> Void = {}`:

```swift
    var canOpenNextLayer = false
    var canOpenPreviousLayer = false
    var openNextLayer: () -> Void = {}
    var openPreviousLayer: () -> Void = {}
```

In `PRSessionCommandsLogic`:

```swift
    static func nextLayerEnabled(_ session: PRSessionActions?) -> Bool { session?.canOpenNextLayer == true }
    static func previousLayerEnabled(_ session: PRSessionActions?) -> Bool { session?.canOpenPreviousLayer == true }
```

In `PRSessionMenuActions`:

```swift
    func openNextLayer() { session?.openNextLayer() }
    func openPreviousLayer() { session?.openPreviousLayer() }
```

In `groups(session:actions:)`, after the watch `Button`:

```swift
            Divider()
            Button("Open Next Layer in Stack", action: actions.openNextLayer)
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(!PRSessionCommandsLogic.nextLayerEnabled(session))
            Button("Open Previous Layer in Stack", action: actions.openPreviousLayer)
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(!PRSessionCommandsLogic.previousLayerEnabled(session))
```

In `ContentView.sessionActions`, add the four arguments:

```swift
            toggleWatch: repository.map(StartScreenActions(model: startScreen).toggleWatch) ?? {},
            canOpenNextLayer: store.canOpenNextLayer,
            canOpenPreviousLayer: store.canOpenPreviousLayer,
            openNextLayer: { store.openNextLayer() },
            openPreviousLayer: { store.openPreviousLayer() }
```

In `CommandPaletteView.allCommands(store:)`, after the `canStopAnalysis` block:

```swift
        if store.canOpenNextLayer {
            commands.append(
                .init(title: "Open next layer in stack", subtitle: "File ▸ Open Next Layer in Stack (⌥⌘])", symbol: "square.3.layers.3d.top.filled") {
                    store.openNextLayer()
                })
        }
        if store.canOpenPreviousLayer {
            commands.append(
                .init(title: "Open previous layer in stack", subtitle: "File ▸ Open Previous Layer in Stack (⌥⌘[)", symbol: "square.3.layers.3d.bottom.filled") {
                    store.openPreviousLayer()
                })
        }
```

- [ ] **Step 4: Run the tests and the build**

Run: `swift test --filter "PRSessionCommandsTests|CommandPaletteViewTests|ContentView"` then `swift build`
Expected: PASS, clean build.

- [ ] **Step 5: Commit**

```bash
git add Sources/Contour/Views/PRSessionCommands.swift Sources/Contour/Views/ContentView.swift \
  Sources/Contour/Views/CommandPaletteView.swift Tests/ContourTests/PRSessionCommandsTests.swift \
  Tests/ContourTests/CommandPaletteViewTests.swift
git commit -m "Move through a stack from the File menu and the command palette

Next and previous layer sit in their own group after the watch item, with
⌥⌘] and ⌥⌘[, and appear in ⌘K only when the open layer has that
neighbour.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Documentation and the spec and plan files

**Files:**
- Modify: `DESIGN.md` §4.2 (after the facts-line sentence), §8 (new paragraph before "Posting reviews"), §9 (context file sentence), §13 (cache bullet)
- Modify: `README.md` (new subsection after "No waiting for the whole analysis")
- Add: `docs/superpowers/specs/2026-10-02-stacked-pull-requests-design.md`, `docs/superpowers/plans/2026-10-06-stacked-pull-requests-know-the-stack.md` (both already written in the primary checkout; copy them into the worktree)

- [ ] **Step 1: DESIGN.md §4.2**

After the sentence ending `(... \`PRGlance\`) that omits whatever the source couldn't tell;`, insert a sentence in the same paragraph before `**What changed**`:

```
when the pull request is one layer of a stack, a strip under the metadata line names its
position ("Part 3 of 7 in a stack") with one chip per layer, the opened one filled, cached
ones ticked, each opening that layer (`Views/Summary/StackStrip.swift`);
```

- [ ] **Step 2: DESIGN.md §8**

Before the paragraph starting `Posting reviews back to GitHub`, add:

```markdown
**Stacked pull requests** are recognised from branch chaining alone
(`Services/StackDiscovery.swift`): the parent of a layer is the open pull request whose head
branch is this one's base branch, found with `gh pr list --head <base>` or
`GET /pulls?head=owner:<base>`; the children are the open pull requests whose base is this one's
head, with `--base` or `?base=`. The walk descends until nothing matches, climbs while exactly
one child matches, stops on a repeated branch and at 32 layers, and ignores rows from forks.
One call per link, so a seven-layer stack opened at the bottom costs seven calls out of the
anonymous 60 per hour. Branch names are author-controlled: a name that fails git's refname
rules is treated as "no parent" rather than passed to `gh`, and is percent-encoded for REST.
Discovery runs beside the checkout and never fails a review; a failure goes to the technical
log and the pull request is reviewed as a plain one.
```

- [ ] **Step 3: DESIGN.md §9 and §13**

In §9, change `containing PR title/body/commits/comments/diff, all wrapped in` to `containing PR title/body/commits/comments/diff and, for a stacked pull request, its position in the stack and the other layers' titles, all author content wrapped in`.

In §13, after the `Analysis cache` bullet, add:

```markdown
- **Stacks.** Each layer of a stacked pull request is cached as an ordinary entry under its
  own number, head and base. The pipeline reports which layers already have a complete entry
  when it emits the stack, so the strip can mark them; merging a lower layer retargets the one
  above it, which moves its base SHA and misses the cache as it should.
```

- [ ] **Step 4: README.md**

After the "No waiting for the whole analysis" paragraph, before `## Why trust it`:

```markdown
### Stacked pull requests

When a pull request is one layer of a stack, Contour notices from the branch chain alone and
shows the whole stack under the title: part 3 of 7, one chip per layer, click to open any of
them. Each layer is reviewed on its own diff, and the analysis is told which layers are
already in the checkout and which build on this one, so code that nothing calls yet is read
as a later layer's job rather than dead code. Next and previous layer are in the File menu
(⌥⌘] and ⌥⌘[) and in ⌘K.
```

- [ ] **Step 5: Copy the spec and plan into the worktree and commit**

```bash
git add DESIGN.md README.md docs/superpowers/specs/2026-10-02-stacked-pull-requests-design.md \
  docs/superpowers/plans/2026-10-06-stacked-pull-requests-know-the-stack.md
git commit -m "Document stacked pull request discovery and the stack strip

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Local gates, coverage, and the pull request

- [ ] **Step 1: Format, lint, build, test**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift
swiftlint lint --strict
swift build
swift test --enable-code-coverage
scripts/periphery.sh
```

Commit any formatter changes with the message `Format` plus the attribution line. Periphery will report `StackLayerStatus` cases or `PRStack` members only if something is unused; remove rather than baseline.

- [ ] **Step 2: Coverage of touched files**

```sh
TEST_BINARY="$(find .build -type f -path '*.xctest/Contents/MacOS/*' -print -quit)"
PROFDATA="$(find .build -type f -name 'default.profdata' -print -quit)"
xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFDATA" -ignore-filename-regex='\.build|Tests/' \
  | grep -E "PRStack|StackDiscovery|StackStrip|PromptBuilder|AnalysisPipeline|GraphStore|PRSessionCommands|CommandPaletteView|SummaryView|AnonymousAPISource|ContentView|TOTAL"
```

Every listed file must be at 90%+ and TOTAL must not be below `origin/badges:coverage.json`. If `find -quit` picks the periphery binary, filter the path for `ContourPackageTests`. `StackStrip.swift` below 90% usually means the `.help` or status branch is unexercised; the render test with `[1: .cached]` covers the symbol branch.

- [ ] **Step 3: Push and open the PR**

```sh
git push -u origin HEAD
gh pr create --title "Know the stack a pull request belongs to" --body "$(cat <<'EOF'
## Summary
- Discover a stacked pull request from branch chaining (gh and anonymous REST), one call per link
- Tell every analysis stage where the layer sits and which layers are already in the checkout
- Show the stack under the Overview title with a chip per layer; File menu and ⌘K move between layers
- Spec: docs/superpowers/specs/2026-10-02-stacked-pull-requests-design.md (PR 1 of 2; background analysis of the whole stack follows)

## Test plan
- [ ] `swift test` green, coverage of every touched file at 90%+
- [ ] `CONTOUR_MOCK_ANALYSIS=1 swift run Contour`, open https://github.com/cli/cli/pull/14452: the header shows "Part 3 of 7 in a stack", chips open other layers, ⌥⌘] moves up
- [ ] Open a plain pull request: no strip, menu items disabled

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Then follow the `ship` skill §5 to §8: watch CI, fix, squash-merge when green, remove the worktree.
