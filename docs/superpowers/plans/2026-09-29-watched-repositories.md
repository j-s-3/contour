# Watched Repositories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the start screen into a two-pane source browser and let the user watch repositories, each listing its 10 newest open pull requests that were not opened by a bot.

**Architecture:** A `StartScreenModel` (`@Observable`, `@MainActor`) owned by `ContentView` holds every source, the remembered selection and each watched repository's load state; views read it and stay thin. Pull request lists come from a `WatchedPullRequests` service with one transport per `GitHubAccessMode` and pure parsers. All decisions that can be pure functions live in `StartScreenLogic`.

**Tech Stack:** Swift 6.4, SwiftUI, macOS 15+, Swift Testing, `gh` CLI, GitHub REST API.

**Spec:** `docs/superpowers/specs/2026-09-29-watched-repositories-design.md`

**Implementation model:** Claude Opus 5.5 (`claude-opus-5-5`). Dispatch every implementer and reviewer subagent with `model: "opus"`.

## Global Constraints

- The package builds only on macOS with the Swift 6.4 toolchain. Swift language mode 6, strict concurrency.
- Both targets build with warnings as errors. Any compiler warning fails the build.
- No code comments in Swift sources or tests: no `//`, `///`, `/* */`, no `// MARK:`.
- 4-space indent, 120-column lines. Run the formatter before every commit.
- Every new or touched file stays at 90% line coverage or above; the overall figure must not drop.
- New test suites use Swift Testing (`@Test`, `#expect`), not XCTest.
- Fixtures under `Tests/ContourTests/Fixtures/` are captured real output, never hand-written. Provenance goes in `Fixtures/README.md`.
- User-facing failure text is written in the reviewer's terms. Raw stderr and HTTP bodies go to the log only.
- Periphery must report nothing new. Remove code that becomes unused.
- No harness call is added. Security invariants in `CLAUDE.md` are untouched.
- Every list on the start screen shows at most 10 rows.
- Two pull requests, each through the repository's `ship` skill (`.claude/skills/ship/SKILL.md`): Part 1 is Tasks 1 to 5, Part 2 is Tasks 6 to 12.
- Commit messages carry the rationale, and end with the attribution footer your session specifies.

### Commands used throughout

```sh
swift build
swift test --filter <SuiteName>
swift test --filter <SuiteName>/<testName>
swift format --in-place --recursive --parallel Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift
swiftlint lint --strict
scripts/periphery.sh
```

Coverage for one file:

```sh
swift test --enable-code-coverage
TEST_BINARY="$(find .build -type f -path '*.xctest/Contents/MacOS/*' -print -quit)"
PROFDATA="$(find .build -type f -name 'default.profdata' -print -quit)"
xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFDATA" -ignore-filename-regex='\.build|Tests/' | grep -E 'Start|Watched|PullRequestRows|Preferences|PRSessionCommands|ContentView|AnalyzingView|FailedView|TOTAL'
```

## Review Focus

Inputs the spec implies but does not spell out. Each has a test in the task named.

1. **Repository names that differ only in case** (`Acme/API` then `acme/api`). Watching the second selects the first instead of adding a duplicate, and the `review requested` label still matches. Tests in Task 9.
2. **A repository removed while its fetch is in flight.** The late result is discarded; no state reappears for a repository that is no longer watched. Test in Task 9.
3. **Every one of the newest 30 open pull requests is from a bot.** The pane says "The newest 30 open pull requests are all automated.", not "No open pull requests." Tests in Tasks 7 and 9.
4. **Stored values that are no longer valid**: a remembered selection naming a repository that was removed, or a watch list edited by hand to contain `--flag/x`. Selection falls back; invalid entries are dropped on read. Tests in Tasks 3 and 9.
5. **Titles that are very long, contain newlines, or look like Markdown.** The row stays one line and shows the text verbatim. Test in Task 10.

## File Structure

| File | Responsibility | Part |
|---|---|---|
| `Sources/Contour/Views/Analysis/AnalyzingView.swift` | `AnalyzingView`, `AnalysisConsoleView`, moved unchanged | 1 |
| `Sources/Contour/Views/Analysis/FailedView.swift` | `FailedView`, moved unchanged | 1 |
| `Sources/Contour/Views/Start/StartSource.swift` | The identity of a sidebar source and its stored form | 1 |
| `Sources/Contour/Views/Start/StartScreenLogic.swift` | Every pure decision the start screen makes | 1, 2 |
| `Sources/Contour/Views/Start/StartScreenModel.swift` | State: sources, selection, load states | 1, 2 |
| `Sources/Contour/Views/Start/StartScreenView.swift` | Split view, URL field, clipboard offer, welcome | 1 |
| `Sources/Contour/Views/Start/StartSidebar.swift` | Sidebar rows and the Watched group | 1, 2 |
| `Sources/Contour/Views/Start/StartSourceList.swift` | The list for the selected source | 1, 2 |
| `Sources/Contour/Views/Start/PullRequestRows.swift` | `PullRequestRow`, `ClipboardOfferRow`, `StartListHeader` | 1, 2 |
| `Sources/Contour/Views/Start/StartScreenActions.swift` | Closures the views call, testable without a view | 2 |
| `Sources/Contour/Views/Start/WatchedPullRequestsList.swift` | A watched repository's list in each state | 2 |
| `Sources/Contour/Views/Start/WatchRepositoryPopover.swift` | The add popover | 2 |
| `Sources/Contour/Models/WatchedRepository.swift` | `WatchedRepository`, its parser and validation | 2 |
| `Sources/Contour/Services/WatchedPullRequests.swift` | Fetch, both parsers, bot filter, failure text | 2 |
| `Sources/Contour/Services/Preferences.swift` | `lastStartSource` (1), `watchedRepositories` (2) | 1, 2 |
| `Sources/Contour/Services/AnonymousAPISource.swift` | One new method: open pull requests for a repository | 2 |
| `Sources/Contour/Views/ContentView.swift` | Owns the model; passes the watch toggle to the menu | 1, 2 |
| `Sources/Contour/Views/PRSessionCommands.swift` | The File menu's watch toggle | 2 |
| `Sources/Contour/Views/OnboardingView.swift` | Deleted at the end of Part 1 | 1 |

---

# Part 1: Restructure the start screen

Ship as one pull request titled "Turn the start screen into a source browser".

Before Task 1, inside the worktree the `ship` skill created, copy in the two documents that exist only in the primary checkout, and commit them:

```sh
mkdir -p docs/superpowers/plans
cp /Users/jstephens/Projects/personal/contour/docs/superpowers/specs/2026-09-29-watched-repositories-design.md docs/superpowers/specs/
cp /Users/jstephens/Projects/personal/contour/docs/superpowers/plans/2026-09-29-watched-repositories.md docs/superpowers/plans/
git add docs/superpowers
git commit -m "Add the watched repositories spec and plan"
```

### Task 1: Move the analysis screens out of OnboardingView.swift

`OnboardingView.swift` is 508 lines holding four unrelated screens. This task moves three of them out, unchanged, so the start screen can be replaced without touching them.

**Files:**
- Create: `Sources/Contour/Views/Analysis/AnalyzingView.swift`
- Create: `Sources/Contour/Views/Analysis/FailedView.swift`
- Modify: `Sources/Contour/Views/OnboardingView.swift` (remove `AnalyzingView`, `AnalysisConsoleView`, `FailedView`)
- Create: `Tests/ContourTests/AnalyzingViewTests.swift`
- Create: `Tests/ContourTests/AnalyzingViewRenderTests.swift`
- Modify: `Tests/ContourTests/OnboardingViewTests.swift`, `OnboardingViewRenderTests.swift`, `OnboardingViewHostingTests.swift` (remove the moved tests)

**Interfaces:**
- Consumes: nothing.
- Produces: `AnalyzingView`, `AnalysisConsoleView`, `FailedView` with unchanged names and signatures.

- [ ] **Step 1: Move the three views**

Cut `struct AnalyzingView` and `struct AnalysisConsoleView` from `OnboardingView.swift`, verbatim, into `Sources/Contour/Views/Analysis/AnalyzingView.swift` under these imports:

```swift
import SwiftUI
```

Cut `struct FailedView` verbatim into `Sources/Contour/Views/Analysis/FailedView.swift` under the same import.

- [ ] **Step 2: Move their pure tests**

Create `Tests/ContourTests/AnalyzingViewTests.swift`:

```swift
import Foundation
import Testing

@testable import Contour

struct AnalyzingViewTests {
}
```

Move these four tests from `OnboardingViewTests` into it, verbatim:
`everyPipelineStageHasAReviewerFacingHeadline`, `latestDetailFallsBackToTheStageNameWithNoLogYet`, `latestDetailShowsOnlyTheStageWhenTheLastEntryHasNoDetail`, `latestDetailCombinesStageAndDetailWhenBothArePresent`.

- [ ] **Step 3: Move their render and hosting tests**

Create `Tests/ContourTests/AnalyzingViewRenderTests.swift`:

```swift
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
@Suite(.serialized)
struct AnalyzingViewRenderTests {
    private func render<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private struct NamespaceHost<Content: View>: View {
        @Namespace var ns
        let content: (Namespace.ID) -> Content
        var body: some View { content(ns) }
    }

    @Observable
    fileprivate final class LogModel {
        var log: [PipelineProgressEntry] = [PipelineProgressEntry(stage: "Opening", detail: "Fetching")]
    }

    fileprivate struct ConsoleHost: View {
        let model: LogModel
        var body: some View { AnalysisConsoleView(log: model.log) }
    }

    private func settle(_ view: NSView) {
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
```

Move into it, verbatim: `analyzingViewLaysOut`, `analysisConsoleLaysOutAndShowsWhenExpanded` and `failedViewLaysOut` from `OnboardingViewRenderTests`, and `consoleFollowsNewEntriesAsTheyArrive` from `OnboardingViewHostingTests`. Remove `LogModel` and `ConsoleHost` from `OnboardingViewHostingTests`.

- [ ] **Step 4: Build and run the moved tests**

Run: `swift build && swift test --filter AnalyzingView && swift test --filter OnboardingView`
Expected: build succeeds; every test passes. The count of tests across these suites equals the count before the move.

- [ ] **Step 5: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add Sources/Contour/Views Tests/ContourTests
git commit -m "Move the analyzing and failed screens into Views/Analysis

OnboardingView.swift held four unrelated screens. The start screen is
about to be replaced, so the three that stay move out unchanged first."
```

### Task 2: StartSource and StartScreenLogic

**Files:**
- Create: `Sources/Contour/Views/Start/StartSource.swift`
- Create: `Sources/Contour/Views/Start/StartScreenLogic.swift`
- Modify: `Sources/Contour/Views/OnboardingView.swift` (remove `OnboardingViewLogic` and `ClipboardOffer`; point call sites at `StartScreenLogic`)
- Rename: `Tests/ContourTests/OnboardingViewTests.swift` to `Tests/ContourTests/StartScreenLogicTests.swift`
- Create: `Tests/ContourTests/StartSourceTests.swift`
- Modify: `Tests/ContourTests/OnboardingViewRenderTests.swift` (`OnboardingViewLogic` becomes `StartScreenLogic`)

**Interfaces:**
- Consumes: `ReviewRequest`, `AnalysisCache.RecentPR`, `PRLink`.
- Produces:
  - `enum StartSource: Hashable, Sendable` with cases `.reviewRequests`, `.recents`, `.watched(String)`, `var storageKey: String`, `init?(storageKey: String)`.
  - `enum ClipboardOffer` (moved, unchanged).
  - `enum StartScreenLogic` with every function `OnboardingViewLogic` had, plus:
    - `static let rowsShown = 10`
    - `static func sources(reviewRequestsAvailable: Bool, watched: [String]) -> [StartSource]`
    - `static func resolvedSelection(remembered: StartSource?, sources: [StartSource]) -> StartSource`
    - `static func showsWelcome(requests: [ReviewRequest], recents: [AnalysisCache.RecentPR], watchedCount: Int) -> Bool`
    - `static func title(for source: StartSource) -> String`
    - `static func symbol(for source: StartSource) -> String`
    - `static func emptyMessage(for source: StartSource) -> String`
    - `static func count(rows: Int) -> String?`

- [ ] **Step 1: Write the failing tests for StartSource**

Create `Tests/ContourTests/StartSourceTests.swift`:

```swift
import Foundation
import Testing

@testable import Contour

struct StartSourceTests {
    @Test func everySourceRoundTripsThroughItsStorageKey() {
        for source in [StartSource.reviewRequests, .recents, .watched("acme/api")] {
            #expect(StartSource(storageKey: source.storageKey) == source)
        }
    }

    @Test func storageKeysAreStableStrings() {
        #expect(StartSource.reviewRequests.storageKey == "reviewRequests")
        #expect(StartSource.recents.storageKey == "recents")
        #expect(StartSource.watched("acme/api").storageKey == "watched:acme/api")
    }

    @Test func unknownOrEmptyStorageKeysDecodeToNothing() {
        #expect(StartSource(storageKey: "") == nil)
        #expect(StartSource(storageKey: "settings") == nil)
        #expect(StartSource(storageKey: "watched:") == nil)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter StartSourceTests`
Expected: FAIL to compile with "cannot find 'StartSource' in scope".

- [ ] **Step 3: Implement StartSource**

Create `Sources/Contour/Views/Start/StartSource.swift`:

```swift
import Foundation

enum StartSource: Hashable, Sendable {
    case reviewRequests
    case recents
    case watched(String)

    private static let watchedPrefix = "watched:"

    var storageKey: String {
        switch self {
        case .reviewRequests: return "reviewRequests"
        case .recents: return "recents"
        case .watched(let id): return Self.watchedPrefix + id
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "reviewRequests": self = .reviewRequests
        case "recents": self = .recents
        default:
            guard storageKey.hasPrefix(Self.watchedPrefix) else { return nil }
            let id = String(storageKey.dropFirst(Self.watchedPrefix.count))
            guard !id.isEmpty else { return nil }
            self = .watched(id)
        }
    }
}
```

- [ ] **Step 4: Move the logic and rename its tests**

Create `Sources/Contour/Views/Start/StartScreenLogic.swift`. Move `enum ClipboardOffer` and the whole body of `enum OnboardingViewLogic` into it from `OnboardingView.swift`, renaming the enum to `StartScreenLogic`:

```swift
import Foundation

enum ClipboardOffer: Equatable {
    case pullRequest(String)
    case unreadLink(changeCount: Int)
}

enum StartScreenLogic {
    static let rowsShown = 10
}
```

with every existing function (`subtitle`, `isDeclined`, both `offer` overloads, `ClipboardReadAction`, `resolveClipboardRead`, `perform`, `resolvedPasteText`, `visibleRequests`, `shouldShowLists`) moved inside `StartScreenLogic` verbatim.

In `OnboardingView.swift`, replace every `OnboardingViewLogic.` with `StartScreenLogic.`. Leave `OnboardingView.rowsShown` at 5: the old screen keeps its five rows until Task 4 removes it.

Rename the test file and suite:

```sh
git mv Tests/ContourTests/OnboardingViewTests.swift Tests/ContourTests/StartScreenLogicTests.swift
```

In it, rename `struct OnboardingViewTests` to `struct StartScreenLogicTests` and replace every `OnboardingViewLogic.` with `StartScreenLogic.`. Do the same replacement in `OnboardingViewRenderTests.swift`.

- [ ] **Step 5: Write the failing tests for the new logic**

Append to `StartScreenLogicTests`:

```swift
    private func request(_ number: Int) -> ReviewRequest {
        ReviewRequest(
            url: "https://github.com/acme/shop/pull/\(number)", repo: "acme/shop", number: number,
            title: "t\(number)", author: "a", isDraft: false, updatedAt: nil)
    }

    private func recent(_ number: Int) -> AnalysisCache.RecentPR {
        AnalysisCache.RecentPR(
            url: "https://github.com/acme/shop/pull/\(number)", repo: "acme/shop", number: number,
            title: "t\(number)", lastOpened: Date(timeIntervalSince1970: TimeInterval(number)))
    }

    @Test func sourcesListReviewRequestsOnlyWhenGHAnswered() {
        #expect(StartScreenLogic.sources(reviewRequestsAvailable: false, watched: []) == [.recents])
        #expect(
            StartScreenLogic.sources(reviewRequestsAvailable: true, watched: []) == [.reviewRequests, .recents])
    }

    @Test func sourcesListWatchedRepositoriesLastInTheOrderGiven() {
        #expect(
            StartScreenLogic.sources(reviewRequestsAvailable: true, watched: ["acme/web", "acme/api"])
                == [.reviewRequests, .recents, .watched("acme/web"), .watched("acme/api")])
    }

    @Test func aRememberedSourceThatStillExistsIsSelected() {
        let sources: [StartSource] = [.reviewRequests, .recents, .watched("acme/api")]
        #expect(StartScreenLogic.resolvedSelection(remembered: .watched("acme/api"), sources: sources)
            == .watched("acme/api"))
    }

    @Test func withNothingRememberedTheFirstSourceIsSelected() {
        #expect(StartScreenLogic.resolvedSelection(remembered: nil, sources: [.reviewRequests, .recents])
            == .reviewRequests)
        #expect(StartScreenLogic.resolvedSelection(remembered: nil, sources: [.recents]) == .recents)
    }

    @Test func aRememberedSourceThatIsGoneFallsBackToTheFirstSource() {
        #expect(
            StartScreenLogic.resolvedSelection(remembered: .watched("acme/gone"), sources: [.reviewRequests, .recents])
                == .reviewRequests)
    }

    @Test func selectionFallsBackToRecentsWhenThereAreNoSourcesAtAll() {
        #expect(StartScreenLogic.resolvedSelection(remembered: nil, sources: []) == .recents)
    }

    @Test func welcomeShowsOnlyWhenNothingIsListedAndNothingIsWatched() {
        #expect(StartScreenLogic.showsWelcome(requests: [], recents: [], watchedCount: 0))
        #expect(!StartScreenLogic.showsWelcome(requests: [request(1)], recents: [], watchedCount: 0))
        #expect(!StartScreenLogic.showsWelcome(requests: [], recents: [recent(1)], watchedCount: 0))
        #expect(!StartScreenLogic.showsWelcome(requests: [], recents: [], watchedCount: 1))
    }

    @Test func everySourceHasATitleASymbolAndAnEmptyMessage() {
        #expect(StartScreenLogic.title(for: .reviewRequests) == "Awaiting your review")
        #expect(StartScreenLogic.title(for: .recents) == "Recently opened")
        #expect(StartScreenLogic.title(for: .watched("acme/api")) == "acme/api")
        #expect(StartScreenLogic.symbol(for: .reviewRequests) == "person.crop.circle.badge.questionmark")
        #expect(StartScreenLogic.symbol(for: .recents) == "clock.arrow.circlepath")
        #expect(StartScreenLogic.symbol(for: .watched("acme/api")) == "eye")
        #expect(StartScreenLogic.emptyMessage(for: .reviewRequests) == "Nothing is waiting for your review.")
        #expect(StartScreenLogic.emptyMessage(for: .recents) == "Pull requests you open will appear here.")
        #expect(StartScreenLogic.emptyMessage(for: .watched("acme/api")) == "No open pull requests.")
    }

    @Test func aCountIsShownOnlyWhenThereAreRows() {
        #expect(StartScreenLogic.count(rows: 0) == nil)
        #expect(StartScreenLogic.count(rows: 3) == "3")
    }

    @Test func listsShowTenRows() {
        #expect(StartScreenLogic.rowsShown == 10)
    }
```

- [ ] **Step 6: Run to verify they fail**

Run: `swift test --filter StartScreenLogicTests`
Expected: FAIL to compile with "type 'StartScreenLogic' has no member 'sources'".

- [ ] **Step 7: Implement the new logic**

Add inside `enum StartScreenLogic`:

```swift
    static func sources(reviewRequestsAvailable: Bool, watched: [String]) -> [StartSource] {
        var sources: [StartSource] = []
        if reviewRequestsAvailable { sources.append(.reviewRequests) }
        sources.append(.recents)
        sources += watched.map(StartSource.watched)
        return sources
    }

    static func resolvedSelection(remembered: StartSource?, sources: [StartSource]) -> StartSource {
        if let remembered, sources.contains(remembered) { return remembered }
        return sources.first ?? .recents
    }

    static func showsWelcome(
        requests: [ReviewRequest], recents: [AnalysisCache.RecentPR], watchedCount: Int
    ) -> Bool {
        requests.isEmpty && recents.isEmpty && watchedCount == 0
    }

    static func title(for source: StartSource) -> String {
        switch source {
        case .reviewRequests: return "Awaiting your review"
        case .recents: return "Recently opened"
        case .watched(let id): return id
        }
    }

    static func symbol(for source: StartSource) -> String {
        switch source {
        case .reviewRequests: return "person.crop.circle.badge.questionmark"
        case .recents: return "clock.arrow.circlepath"
        case .watched: return "eye"
        }
    }

    static func emptyMessage(for source: StartSource) -> String {
        switch source {
        case .reviewRequests: return "Nothing is waiting for your review."
        case .recents: return "Pull requests you open will appear here."
        case .watched: return "No open pull requests."
        }
    }

    static func count(rows: Int) -> String? {
        rows > 0 ? String(rows) : nil
    }
```

- [ ] **Step 8: Run to verify they pass**

Run: `swift build && swift test --filter StartScreenLogicTests && swift test --filter StartSourceTests && swift test --filter OnboardingView`
Expected: PASS.

- [ ] **Step 9: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add Sources/Contour/Views Tests/ContourTests
git commit -m "Name the start screen's sources and decide selection in one place

StartSource identifies a sidebar entry and its stored form.
StartScreenLogic replaces OnboardingViewLogic and gains source order,
selection fallback and the welcome condition as pure functions."
```

### Task 3: StartScreenModel and the remembered selection

**Files:**
- Modify: `Sources/Contour/Services/Preferences.swift`
- Create: `Sources/Contour/Views/Start/StartScreenModel.swift`
- Modify: `Tests/ContourTests/PreferencesTests.swift`
- Create: `Tests/ContourTests/StartScreenModelTests.swift`

**Interfaces:**
- Consumes: `StartSource`, `StartScreenLogic` (Task 2), `Preferences`, `ReviewRequests.fetch(access:)`, `AnalysisCache().recentPRs(limit:)`.
- Produces:
  - `Preferences.lastStartSource: StartSource?`
  - `StartScreenModel.Dependencies` with `loadRecents: () -> [AnalysisCache.RecentPR]`, `loadReviewRequests: @MainActor () async -> [ReviewRequest]?`, and `@MainActor static var live: Dependencies`
  - `StartScreenModel.init(preferences: Preferences, dependencies: Dependencies)`
  - `var recents: [AnalysisCache.RecentPR]`, `var reviewRequests: [ReviewRequest]?`, `var visibleReviewRequests: [ReviewRequest]`
  - `var sources: [StartSource]`, `var selection: StartSource`, `var selectionBinding: Binding<StartSource?>`
  - `var showsWelcome: Bool`
  - `func select(_ source: StartSource)`, `func count(for source: StartSource) -> String?`, `func reload() async`

- [ ] **Step 1: Write the failing Preferences test**

Append to `PreferencesTests` (it already has a `freshDefaults()` helper):

```swift
    @Test func lastStartSourceRoundTripsAndDefaultsToNil() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults, environment: [:])
        #expect(prefs.lastStartSource == nil)
        prefs.lastStartSource = .watched("acme/api")
        #expect(Preferences(defaults: defaults, environment: [:]).lastStartSource == .watched("acme/api"))
        prefs.lastStartSource = nil
        #expect(Preferences(defaults: defaults, environment: [:]).lastStartSource == nil)
    }

    @Test func aStoredStartSourceThatCannotBeReadIsIgnored() {
        let defaults = freshDefaults()
        defaults.set("settings", forKey: "lastStartSource")
        #expect(Preferences(defaults: defaults, environment: [:]).lastStartSource == nil)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PreferencesTests/lastStartSourceRoundTripsAndDefaultsToNil`
Expected: FAIL to compile with "value of type 'Preferences' has no member 'lastStartSource'".

- [ ] **Step 3: Implement the preference**

In `Preferences.swift`, add to `private enum Key`:

```swift
        static let lastStartSource = "lastStartSource"
```

and after `opensInFullScreen`:

```swift
    var lastStartSource: StartSource? {
        get { defaults.string(forKey: Key.lastStartSource).flatMap(StartSource.init(storageKey:)) }
        set { defaults.set(newValue?.storageKey, forKey: Key.lastStartSource) }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter PreferencesTests`
Expected: PASS.

- [ ] **Step 5: Write the failing model tests**

Create `Tests/ContourTests/StartScreenModelTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct StartScreenModelTests {
    private func preferences() -> Preferences {
        let name = "contour.tests.start.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults, environment: [:])
    }

    private func request(_ number: Int) -> ReviewRequest {
        ReviewRequest(
            url: "https://github.com/acme/shop/pull/\(number)", repo: "acme/shop", number: number,
            title: "t\(number)", author: "a", isDraft: false, updatedAt: nil)
    }

    private func recent(_ number: Int) -> AnalysisCache.RecentPR {
        AnalysisCache.RecentPR(
            url: "https://github.com/acme/shop/pull/\(number)", repo: "acme/shop", number: number,
            title: "t\(number)", lastOpened: Date(timeIntervalSince1970: TimeInterval(number)))
    }

    private func model(
        preferences: Preferences, recents: [AnalysisCache.RecentPR] = [], requests: [ReviewRequest]? = nil
    ) -> StartScreenModel {
        StartScreenModel(
            preferences: preferences,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { recents }, loadReviewRequests: { requests }))
    }

    @Test func beforeAnythingLoadsTheOnlySourceIsRecentlyOpened() {
        let model = model(preferences: preferences(), requests: [request(1)])
        #expect(model.sources == [.recents])
        #expect(model.selection == .recents)
        #expect(model.showsWelcome)
    }

    @Test func reviewRequestsBecomeASourceOnceGHAnswers() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: [])
        await model.reload()
        #expect(model.sources == [.reviewRequests, .recents])
        #expect(model.recents.map(\.number) == [1])
    }

    @Test func whenGHCannotAnswerReviewRequestsAreNotASource() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: nil)
        await model.reload()
        #expect(model.sources == [.recents])
        #expect(model.visibleReviewRequests.isEmpty)
    }

    @Test func withNothingRememberedSelectionPrefersReviewRequests() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: [request(1)])
        await model.reload()
        #expect(model.selection == .reviewRequests)
    }

    @Test func aChosenSourceIsRememberedByTheNextModel() async {
        let prefs = preferences()
        let first = model(preferences: prefs, recents: [recent(1)], requests: [request(1)])
        await first.reload()
        first.select(.recents)
        #expect(first.selection == .recents)

        let second = model(preferences: prefs, recents: [recent(1)], requests: [request(1)])
        await second.reload()
        #expect(second.selection == .recents)
    }

    @Test func aRememberedSourceThatNoLongerExistsFallsBack() async {
        let prefs = preferences()
        prefs.lastStartSource = .watched("acme/gone")
        let model = model(preferences: prefs, recents: [recent(1)], requests: [request(1)])
        await model.reload()
        #expect(model.selection == .reviewRequests)
    }

    @Test func aRememberedReviewRequestSelectionReturnsOnceGHAnswers() async {
        let prefs = preferences()
        prefs.lastStartSource = .reviewRequests
        let model = model(preferences: prefs, recents: [recent(1)], requests: [request(1)])
        #expect(model.selection == .recents)
        await model.reload()
        #expect(model.selection == .reviewRequests)
    }

    @Test func welcomeGivesWayAsSoonAsAnySourceHasRows() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: nil)
        await model.reload()
        #expect(!model.showsWelcome)
    }

    @Test func reviewRequestsAreCappedAtTenAndCounted() async {
        let model = model(preferences: preferences(), requests: (1...14).map(request))
        await model.reload()
        #expect(model.visibleReviewRequests.count == 10)
        #expect(model.count(for: .reviewRequests) == "10")
        #expect(model.count(for: .recents) == nil)
        #expect(model.count(for: .watched("acme/api")) == nil)
    }

    @Test func theSelectionBindingReadsAndWritesTheSelection() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: [request(1)])
        await model.reload()
        let binding = model.selectionBinding
        #expect(binding.wrappedValue == .reviewRequests)
        binding.wrappedValue = .recents
        #expect(model.selection == .recents)
        binding.wrappedValue = nil
        #expect(model.selection == .recents)
    }

    @Test func liveDependenciesReadTheRealSources() async {
        let live = StartScreenModel.Dependencies.live
        #expect(live.loadRecents().count <= StartScreenLogic.rowsShown)
    }
}
```

- [ ] **Step 6: Run to verify they fail**

Run: `swift test --filter StartScreenModelTests`
Expected: FAIL to compile with "cannot find 'StartScreenModel' in scope".

- [ ] **Step 7: Implement the model**

Create `Sources/Contour/Views/Start/StartScreenModel.swift`:

```swift
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class StartScreenModel {
    struct Dependencies {
        var loadRecents: () -> [AnalysisCache.RecentPR]
        var loadReviewRequests: @MainActor () async -> [ReviewRequest]?

        @MainActor static var live: Dependencies {
            Dependencies(
                loadRecents: { AnalysisCache().recentPRs(limit: StartScreenLogic.rowsShown) },
                loadReviewRequests: {
                    await ReviewRequests.fetch(access: Preferences.shared.resolvedGitHubAccess)
                })
        }
    }

    private(set) var recents: [AnalysisCache.RecentPR] = []
    private(set) var reviewRequests: [ReviewRequest]?
    private var remembered: StartSource?

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let dependencies: Dependencies

    init(preferences: Preferences, dependencies: Dependencies) {
        self.preferences = preferences
        self.dependencies = dependencies
        remembered = preferences.lastStartSource
    }

    var visibleReviewRequests: [ReviewRequest] {
        StartScreenLogic.visibleRequests(reviewRequests, limit: StartScreenLogic.rowsShown)
    }

    var sources: [StartSource] {
        StartScreenLogic.sources(reviewRequestsAvailable: reviewRequests != nil, watched: [])
    }

    var selection: StartSource {
        StartScreenLogic.resolvedSelection(remembered: remembered, sources: sources)
    }

    var selectionBinding: Binding<StartSource?> {
        Binding(
            get: { self.selection },
            set: { if let source = $0 { self.select(source) } }
        )
    }

    var showsWelcome: Bool {
        StartScreenLogic.showsWelcome(requests: visibleReviewRequests, recents: recents, watchedCount: 0)
    }

    func select(_ source: StartSource) {
        remembered = source
        preferences.lastStartSource = source
    }

    func count(for source: StartSource) -> String? {
        switch source {
        case .reviewRequests: return StartScreenLogic.count(rows: visibleReviewRequests.count)
        case .recents, .watched: return nil
        }
    }

    func reload() async {
        recents = dependencies.loadRecents()
        reviewRequests = await dependencies.loadReviewRequests()
    }
}
```

- [ ] **Step 8: Run to verify they pass**

Run: `swift test --filter StartScreenModelTests`
Expected: PASS, 11 tests.

- [ ] **Step 9: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add Sources/Contour Tests/ContourTests
git commit -m "Hold the start screen's state in a model that outlives the view

StartScreenModel owns the sources and the selection, and remembers the
selection in Preferences. Selection is derived from what is remembered
and what exists, so a remembered review-request selection returns once
gh answers and a removed source falls back without special cases."
```

### Task 4: The source browser view

**Files:**
- Create: `Sources/Contour/Views/Start/PullRequestRows.swift`
- Create: `Sources/Contour/Views/Start/StartSourceList.swift`
- Create: `Sources/Contour/Views/Start/StartSidebar.swift`
- Create: `Sources/Contour/Views/Start/StartScreenView.swift`
- Delete: `Sources/Contour/Views/OnboardingView.swift`
- Modify: `Sources/Contour/Views/Start/StartScreenLogic.swift` (remove `shouldShowLists`)
- Modify: `Sources/Contour/Views/ContentView.swift`
- Rename: `Tests/ContourTests/OnboardingViewRenderTests.swift` to `StartScreenViewRenderTests.swift`
- Rename: `Tests/ContourTests/OnboardingViewHostingTests.swift` to `StartScreenViewHostingTests.swift`
- Modify: `Tests/ContourTests/StartScreenLogicTests.swift` (remove `shouldShowListsIsFalseOnlyWhenBothListsAreEmpty`)

**Interfaces:**
- Consumes: `StartScreenModel` (Task 3), `StartScreenLogic`, `StartSource` (Task 2), `ContourMarkView`, `matchesContourMark(in:)`, `MockAnalysisFixtures`, `GitHubService.normalize`.
- Produces:
  - `StartScreenView(model:initialURL:markNamespace:focusRequest:pasteboard:onSubmit:)`
  - `static func StartScreenView.loadPastedText(from:apply:)` (moved from `OnboardingView`)
  - `StartSidebar(model:markNamespace:)`
  - `StartSourceRow(source:count:)`
  - `StartSourceList(model:onOpen:)`
  - `StartListHeader(title:systemImage:)` with a trailing view builder
  - `PullRequestRow`, `ClipboardOfferRow` (moved, unchanged)
  - `ContentView.init(store:needsOnboarding:startScreen:)`

- [ ] **Step 1: Move the rows**

Create `Sources/Contour/Views/Start/PullRequestRows.swift`. Move `struct ClipboardOfferRow` and `struct PullRequestRow` into it verbatim from `OnboardingView.swift`, with `OnboardingViewLogic` already reading `StartScreenLogic`. Add the list header, which replaces `PullRequestList`:

```swift
import SwiftUI

struct StartListHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

extension StartListHeader where Trailing == EmptyView {
    init(title: String, systemImage: String) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}
```

- [ ] **Step 2: Write the list for the selected source**

Create `Sources/Contour/Views/Start/StartSourceList.swift`:

```swift
import SwiftUI

struct StartSourceList: View {
    let model: StartScreenModel
    var onOpen: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                switch model.selection {
                case .reviewRequests: reviewRequests
                case .recents: recents
                case .watched: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var reviewRequests: some View {
        StartListHeader(
            title: StartScreenLogic.title(for: .reviewRequests),
            systemImage: StartScreenLogic.symbol(for: .reviewRequests))
        if model.visibleReviewRequests.isEmpty {
            StartEmptyMessage(text: StartScreenLogic.emptyMessage(for: .reviewRequests))
        }
        ForEach(model.visibleReviewRequests) { request in
            PullRequestRow(
                title: request.title, repo: request.repo, number: request.number,
                detail: request.isDraft ? "\(request.author) · draft" : request.author,
                date: request.updatedAt, dateVerb: "updated", url: request.url, onOpen: onOpen
            )
        }
    }

    @ViewBuilder
    private var recents: some View {
        StartListHeader(
            title: StartScreenLogic.title(for: .recents), systemImage: StartScreenLogic.symbol(for: .recents))
        if model.recents.isEmpty {
            StartEmptyMessage(text: StartScreenLogic.emptyMessage(for: .recents))
        }
        ForEach(model.recents) { recent in
            PullRequestRow(
                title: recent.title, repo: recent.repo, number: recent.number,
                detail: nil, date: recent.lastOpened, dateVerb: "opened", url: recent.url,
                onOpen: onOpen
            )
        }
    }
}

struct StartEmptyMessage: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }
}
```

- [ ] **Step 3: Write the sidebar**

Create `Sources/Contour/Views/Start/StartSidebar.swift`:

```swift
import SwiftUI

struct StartSidebar: View {
    let model: StartScreenModel
    var markNamespace: Namespace.ID

    static let markHeight: CGFloat = 24

    var body: some View {
        List(selection: model.selectionBinding) {
            ForEach(model.sources, id: \.self) { source in
                StartSourceRow(source: source, count: model.count(for: source))
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !model.showsWelcome {
                ContourMarkView()
                    .matchesContourMark(in: markNamespace)
                    .frame(height: Self.markHeight)
            }
            Text("Contour")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct StartSourceRow: View {
    let source: StartSource
    let count: String?

    var body: some View {
        Label {
            Text(verbatim: StartScreenLogic.title(for: source))
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: StartScreenLogic.symbol(for: source))
        }
        .badge(count.map { Text(verbatim: $0) })
    }
}
```

The mark appears in exactly one place at a time: large in the welcome pane, or small here. Two views carrying the same matched-geometry id at once would break the glide into the opening screen.

- [ ] **Step 4: Write the screen**

Create `Sources/Contour/Views/Start/StartScreenView.swift`. The clipboard functions (`checkClipboard`, `openUnreadClipboard`, `clipboardOfferRow`, `submit`, `loadPastedText`) are moved verbatim from `OnboardingView`, with `OnboardingViewLogic` reading `StartScreenLogic`:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StartScreenView: View {
    let model: StartScreenModel
    @State private var urlText: String
    @FocusState private var urlFieldFocused: Bool
    @State private var clipboardOffer: ClipboardOffer?
    @State private var declinedChangeCount: Int?
    var markNamespace: Namespace.ID
    var focusRequest: Int
    var onSubmit: (String) -> Void
    nonisolated(unsafe) private let pasteboard: NSPasteboard

    init(
        model: StartScreenModel, initialURL: String? = nil, markNamespace: Namespace.ID, focusRequest: Int = 0,
        pasteboard: NSPasteboard = .general, onSubmit: @escaping (String) -> Void
    ) {
        self.model = model
        self.pasteboard = pasteboard
        _urlText = State(initialValue: initialURL ?? "")
        self.markNamespace = markNamespace
        self.focusRequest = focusRequest
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationSplitView {
            StartSidebar(model: model, markNamespace: markNamespace)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Contour")
        .onAppear { urlFieldFocused = true }
        .onChange(of: focusRequest) { urlFieldFocused = true }
        .animation(.easeInOut(duration: 0.2), value: clipboardOffer)
        .animation(.easeInOut(duration: 0.25), value: model.showsWelcome)
        .task {
            await checkClipboard()
            await model.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkClipboard() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.showsWelcome {
            VStack(spacing: 0) {
                Spacer()
                ContourMarkView()
                    .matchesContourMark(in: markNamespace)
                    .frame(height: ContourMarkView.heroHeight)
                Text("Contour")
                    .font(.system(size: 28, weight: .semibold))
                    .padding(.top, 22)
                Text("Understand the change, not just the diff.")
                    .font(.title3)
                    .padding(.top, 10)
                Text("See what changed, how the system works, and which decisions deserve your attention.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .padding(.top, 6)
                openControls(alignment: .center)
                    .padding(.top, 28)
                Spacer()
                Spacer().frame(height: 60)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                openControls(alignment: .leading)
                StartSourceList(model: model, onOpen: onSubmit)
                    .padding(.top, 20)
            }
            .padding(24)
            .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func openControls(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            HStack {
                TextField("Paste a GitHub pull request URL…", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 320, maxWidth: 520)
                    .focused($urlFieldFocused)
                    .onSubmit(submit)
                    .onPasteCommand(of: [.text, .url]) { providers in
                        Self.loadPastedText(from: providers) { urlText = $0 }
                    }
                Button {
                    if let clip = pasteboard.string(forType: .string) {
                        urlText = StartScreenLogic.resolvedPasteText(clip)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Paste from clipboard")
                Button("Open", action: submit)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(GitHubService.normalize(urlText) == nil)
            }

            if let offer = clipboardOffer {
                clipboardOfferRow(offer)
                    .padding(.top, 14)
                    .transition(.opacity)
            }

            if MockAnalysisFixtures.isEnabled {
                Button {
                    onSubmit(MockAnalysisFixtures.sourcePRURL)
                } label: {
                    Label("Load test data", systemImage: "testtube.2")
                }
                .help(MockAnalysisFixtures.sourcePRURL)
                .padding(.top, 16)
            }
        }
    }
}
```

followed, inside the same struct, by the five moved functions.

- [ ] **Step 5: Remove what the old layout needed**

Delete `Sources/Contour/Views/OnboardingView.swift`. By now it holds only `OnboardingView`, `PullRequestLists` and `PullRequestList`.

In `StartScreenLogic.swift`, delete `shouldShowLists`. In `StartScreenLogicTests.swift`, delete `shouldShowListsIsFalseOnlyWhenBothListsAreEmpty`.

- [ ] **Step 6: Give ContentView the model**

In `ContentView.swift`, add the state and the initializer parameter:

```swift
    @State private var startScreen: StartScreenModel

    init(store: GraphStore = GraphStore(), needsOnboarding: Bool? = nil, startScreen: StartScreenModel? = nil) {
        _store = State(initialValue: store)
        _needsOnboarding = State(initialValue: needsOnboarding ?? !Preferences.shared.hasCompletedOnboarding)
        _startScreen = State(
            initialValue: startScreen ?? StartScreenModel(preferences: .shared, dependencies: .live))
    }
```

Add one property and use it in both places `mainBody` built an `OnboardingView` (the `.idle` case and the `.review` case with no graph):

```swift
    private var startScreenView: some View {
        StartScreenView(
            model: startScreen, initialURL: store.lastPRURL, markNamespace: markNamespace,
            focusRequest: urlFieldFocusRequest, onSubmit: actions.load
        )
    }
```

- [ ] **Step 7: Rename and rewrite the view tests**

```sh
git mv Tests/ContourTests/OnboardingViewRenderTests.swift Tests/ContourTests/StartScreenViewRenderTests.swift
git mv Tests/ContourTests/OnboardingViewHostingTests.swift Tests/ContourTests/StartScreenViewHostingTests.swift
```

Replace the contents of `StartScreenViewRenderTests.swift`:

```swift
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct StartScreenViewRenderTests {
    private func render<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 1080, height: 720)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private struct NamespaceHost<Content: View>: View {
        @Namespace var ns
        let content: (Namespace.ID) -> Content
        var body: some View { content(ns) }
    }

    private func preferences() -> Preferences {
        let name = "contour.tests.start.render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults, environment: [:])
    }

    private func requests() -> [ReviewRequest] {
        [
            ReviewRequest(
                url: "u1", repo: "acme/shop", number: 1, title: "t1", author: "a", isDraft: true, updatedAt: Date()),
            ReviewRequest(
                url: "u2", repo: "acme/shop", number: 2, title: "t2", author: "b", isDraft: false, updatedAt: nil),
        ]
    }

    private func recents() -> [AnalysisCache.RecentPR] {
        [AnalysisCache.RecentPR(url: "u3", repo: "acme/shop", number: 3, title: "t3", lastOpened: Date())]
    }

    private func loaded(
        recents: [AnalysisCache.RecentPR], requests: [ReviewRequest]?, selecting source: StartSource? = nil
    ) async -> StartScreenModel {
        let model = StartScreenModel(
            preferences: preferences(),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { recents }, loadReviewRequests: { requests }))
        await model.reload()
        if let source { model.select(source) }
        return model
    }

    @Test func theWelcomeLaysOutWhenNothingIsListed() async {
        let model = await loaded(recents: [], requests: nil)
        #expect(model.showsWelcome)
        _ = render(NamespaceHost { StartScreenView(model: model, markNamespace: $0, onSubmit: { _ in }) })
    }

    @Test func theBrowserLaysOutForEachSource() async {
        for source in [StartSource.reviewRequests, .recents] {
            let model = await loaded(recents: recents(), requests: requests(), selecting: source)
            _ = render(
                NamespaceHost {
                    StartScreenView(
                        model: model, initialURL: "https://github.com/acme/shop/pull/1", markNamespace: $0,
                        focusRequest: 2, onSubmit: { _ in })
                })
        }
    }

    @Test func eachSourceListLaysOutWithAndWithoutRows() async {
        let full = await loaded(recents: recents(), requests: requests(), selecting: .reviewRequests)
        #expect(render(StartSourceList(model: full, onOpen: { _ in })).height > 0)
        full.select(.recents)
        #expect(render(StartSourceList(model: full, onOpen: { _ in })).height > 0)

        let empty = await loaded(recents: [], requests: [], selecting: .reviewRequests)
        #expect(render(StartSourceList(model: empty, onOpen: { _ in })).height > 0)
        empty.select(.recents)
        #expect(render(StartSourceList(model: empty, onOpen: { _ in })).height > 0)
    }

    @Test func theSidebarLaysOutWithAndWithoutTheMark() async {
        let welcome = await loaded(recents: [], requests: nil)
        let browsing = await loaded(recents: recents(), requests: requests())
        for model in [welcome, browsing] {
            _ = render(NamespaceHost { StartSidebar(model: model, markNamespace: $0) })
        }
    }

    @Test func sourceRowsLayOutWithAndWithoutACount() {
        #expect(render(StartSourceRow(source: .reviewRequests, count: "3")).width > 0)
        #expect(render(StartSourceRow(source: .recents, count: nil)).width > 0)
    }

    @Test func listHeadersLayOutWithAndWithoutATrailingView() {
        #expect(render(StartListHeader(title: "Recently opened", systemImage: "clock")).width > 0)
        #expect(render(StartListHeader(title: "acme/api", systemImage: "eye") { Text("now") }).width > 0)
    }

    @Test func pullRequestRowsLayOut() {
        let size = render(
            VStack {
                PullRequestRow(
                    title: "Fix it", repo: "acme/shop", number: 3, detail: "jdoe · draft",
                    date: Date(), dateVerb: "updated",
                    url: "https://github.com/acme/shop/pull/3", onOpen: { _ in })
                PullRequestRow(
                    title: "Another", repo: "acme/shop", number: 4, detail: nil,
                    date: nil, dateVerb: "opened",
                    url: "https://github.com/acme/shop/pull/4", onOpen: { _ in })
            }
        )
        #expect(size.width > 0 && size.height > 0)
    }

    @Test func clipboardOfferRowLaysOutForBothOffers() {
        for offer in [ClipboardOffer.pullRequest("https://github.com/acme/shop/pull/1"), .unreadLink(changeCount: 4)] {
            _ = render(ClipboardOfferRow(offer: offer, onOpen: { _ in }, onOpenUnread: { _ in }, onDismiss: {}))
        }
    }

    @Test func performCarriesOutEachClipboardReadAction() {
        var opened: [String] = []
        var filled: [String] = []
        StartScreenLogic.perform(.open("u"), open: { opened.append($0) }, fillField: { filled.append($0) })
        StartScreenLogic.perform(.fillField("text"), open: { opened.append($0) }, fillField: { filled.append($0) })
        StartScreenLogic.perform(.doNothing, open: { opened.append($0) }, fillField: { filled.append($0) })
        #expect(opened == ["u"])
        #expect(filled == ["text"])
    }

    @Test func loadPastedTextAppliesTheResolvedText() async {
        StartScreenView.loadPastedText(from: [], apply: { _ in Issue.record("nothing was pasted") })

        let applied = await withCheckedContinuation { continuation in
            StartScreenView.loadPastedText(
                from: [NSItemProvider(object: "see github.com/acme/shop/pull/3" as NSString)]
            ) { continuation.resume(returning: $0) }
        }
        #expect(applied == "https://github.com/acme/shop/pull/3")
    }
}
```

In `StartScreenViewHostingTests.swift`, rename the suite to `StartScreenViewHostingTests` and replace the `host` function so it builds the model from the recorder; every existing test body stays as it is:

```swift
    private func preferences() -> Preferences {
        let name = "contour.tests.start.hosting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults, environment: [:])
    }

    private func host(
        recorder: Recorder, board: NSPasteboard, initialURL: String? = nil, requests: [ReviewRequest]? = nil
    ) -> NSWindow {
        _ = NSApplication.shared
        let recentPRs = recents()
        let model = StartScreenModel(
            preferences: preferences(),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: {
                    recorder.recentLoads += 1
                    return recentPRs
                },
                loadReviewRequests: {
                    recorder.requestLoads += 1
                    return requests
                }))
        let view = NamespaceHost { namespace in
            StartScreenView(
                model: model, initialURL: initialURL, markNamespace: namespace, pasteboard: board,
                onSubmit: { recorder.submitted.append($0) })
        }
        let hosting = NSHostingView(rootView: view)
        let window = HeadlessWindow(size: NSSize(width: 1080, height: 720), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        return window
    }
```

Add one test to the hosting suite:

```swift
    @Test func theModelKeepsItsListsAfterTheViewGoesAway() {
        let recorder = Recorder()
        let recentPRs = recents()
        let model = StartScreenModel(
            preferences: preferences(),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: {
                    recorder.recentLoads += 1
                    return recentPRs
                },
                loadReviewRequests: { nil }))
        let view = NamespaceHost { namespace in
            StartScreenView(model: model, markNamespace: namespace, onSubmit: { _ in })
        }
        let hosting = NSHostingView(rootView: view)
        let window = HeadlessWindow(size: NSSize(width: 1080, height: 720), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        window.close()
        #expect(model.recents.map(\.number) == [7])
    }
```

- [ ] **Step 8: Build and run the affected suites**

Run: `swift build && swift test --filter StartScreen && swift test --filter ContentView`
Expected: PASS. If `ContentViewHostingTests` or `ContentViewTests` named `OnboardingView`, the build fails and names the line; replace it with `StartScreenView`.

- [ ] **Step 9: See it**

Follow the in-process snapshot procedure: add a temporary, uncommitted `Sources/Contour/ZZDebugSnap.swift` that writes `window.contentView.superview` to PNG (use a directory unique to this session), launch with `swift run Contour`, and capture the start screen at 1080×772 and at 1728×1080. Check: the sidebar lists the sources, the small mark sits in the sidebar header, the URL field is at the top of the pane, and opening a PR still glides the mark to the centre. With no recents and no `gh`, check the welcome fills the pane. Delete the debug file afterwards and confirm `git status` does not list it.

- [ ] **Step 10: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add -A Sources/Contour Tests/ContourTests
git commit -m "Show the start screen as a sidebar of sources beside one list

The centered hero over two five-row columns had no room for a third
source. Sources now sit in a sidebar on the same NavigationSplitView as
the review, with one list of up to ten rows beside it. The large mark
and proposition remain as the pane's content when nothing is listed.
ContentView owns the model so lists survive a round trip into a review."
```

### Task 5: Document the new start screen and ship Part 1

**Files:**
- Modify: `DESIGN.md` §4.1a

**Interfaces:**
- Consumes: everything from Tasks 1 to 4.
- Produces: a merged pull request.

- [ ] **Step 1: Rewrite the Welcome bullet in DESIGN.md §4.1a**

Replace the bullet that begins `- **Welcome.**` with:

```markdown
- **Start.** A two-pane browser on the same split view as the review. The sidebar lists
  where review work comes from: PRs awaiting the user's review
  (`gh search prs --review-requested=@me --state=open`, listed only when `gh` can
  answer) and the PRs opened most recently. The pane beside it holds the URL field and
  the selected source's list, up to ten rows; the source chosen last is remembered.
  Recent PRs reopen instantly from the analysis cache. The URL field covers the rest.
  The mark rests small in the sidebar header and stays still. Idle motion would pull
  the eye away from the list.
- **Welcome.** When no source has anything to list, the pane is the welcome instead:
  the large mark, "Contour", the proposition ("Understand the change, not just the
  diff.") and the URL field. The sidebar header then shows the name alone, so the mark
  is only ever in one place.
```

In the `- **Opening.**` bullet, change "carries over from the welcome screen" to "carries over from the start screen".

- [ ] **Step 2: Run every local gate**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift
swiftlint lint --strict
swift build
swift test --enable-code-coverage
scripts/periphery.sh
```

Expected: every command exits 0. Periphery reports nothing. If it reports `StartListHeader`'s trailing initializer or `StartSource.watched` as unused, leave them: Part 2 uses both, and the render tests above already exercise them so Periphery sees a use.

- [ ] **Step 3: Check coverage of the touched files**

Run the coverage command from "Commands used throughout".
Expected: every file under `Views/Start/`, `Views/Analysis/AnalyzingView.swift`, `Views/Analysis/FailedView.swift`, `Services/Preferences.swift` and `Views/ContentView.swift` is at 90.00% or above, and TOTAL is not below the figure on `main`.

- [ ] **Step 4: Commit and ship**

```sh
git add DESIGN.md
git commit -m "Describe the start screen as a source browser in DESIGN.md"
```

Continue with steps 4 to 8 of the `ship` skill: push, open the pull request, watch CI, squash-merge when green, remove the worktree.

---

# Part 2: Watched repositories

Ship as one pull request titled "Watch repositories from the start screen". Start only after Part 1 has merged, in a fresh worktree off `origin/main`.

Part 1 as merged differs from Tasks 3 and 4 as written in two ways that Part 2 builds on: `StartScreenModel` has no `reload()`; it has `loadRecents()` (synchronous) and `loadReviewRequests()` (async, and it skips its write when its task was cancelled), and `StartScreenView`'s `.task` is `model.loadRecents(); await checkClipboard(); await model.loadReviewRequests()`. Task 9 replaces the second loader's role with `loadRemoteSources()` and Task 10 points the view at it.

### Task 6: WatchedRepository

**Files:**
- Create: `Sources/Contour/Models/WatchedRepository.swift`
- Create: `Tests/ContourTests/WatchedRepositoryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct WatchedRepository: Codable, Equatable, Identifiable, Sendable` with `owner: String`, `name: String`, `id: String` (`"owner/name"`), `url: URL?`
  - `func matches(_ other: String) -> Bool` (case-insensitive comparison with an `owner/name` string)
  - `static func parse(_ input: String) -> WatchedRepository?`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ContourTests/WatchedRepositoryTests.swift`:

```swift
import Foundation
import Testing

@testable import Contour

struct WatchedRepositoryTests {
    @Test(arguments: [
        "acme/api",
        "  acme/api  ",
        "acme/api/",
        "https://github.com/acme/api",
        "https://github.com/acme/api/",
        "https://github.com/acme/api.git",
        "http://github.com/acme/api",
        "github.com/acme/api",
        "www.github.com/acme/api",
        "https://www.github.com/acme/api/pull/12/files",
        "https://github.com/acme/api/pull/12",
        "https://github.com/acme/api?tab=readme-ov-file",
        "https://github.com/acme/api#readme",
        "https://GitHub.com/acme/api",
    ])
    func everyAcceptedFormNamesTheSameRepository(input: String) {
        #expect(WatchedRepository.parse(input) == WatchedRepository(owner: "acme", name: "api"))
    }

    @Test(arguments: [
        "",
        "   ",
        "acme",
        "acme/",
        "/api",
        "acme/api/extra",
        "-acme/api",
        "--flag/x",
        "acme/a b",
        "acme/api;rm",
        "acme/..",
        "acme/.",
        "acmé/api",
        "https://gitlab.com/acme/api",
        "https://evilgithub.com/acme/api",
        "https://github.com.evil.example/acme/api",
        "ftp://github.com/acme/api",
        "https://github.com/acme",
    ])
    func inputThatIsNotAGitHubRepositoryIsRejected(input: String) {
        #expect(WatchedRepository.parse(input) == nil)
    }

    @Test func namesMayContainDotsUnderscoresAndHyphens() {
        #expect(
            WatchedRepository.parse("my-org_1/my.repo-name_2")
                == WatchedRepository(owner: "my-org_1", name: "my.repo-name_2"))
    }

    @Test func ownersAndNamesLongerThanGitHubAllowsAreRejected() {
        let owner = String(repeating: "a", count: 40)
        let name = String(repeating: "b", count: 101)
        #expect(WatchedRepository.parse("\(owner)/api") == nil)
        #expect(WatchedRepository.parse("acme/\(name)") == nil)
        #expect(WatchedRepository.parse("\(owner.dropLast())/\(name.dropLast())") != nil)
    }

    @Test func idJoinsOwnerAndNameAndURLPointsAtGitHub() {
        let repository = WatchedRepository(owner: "acme", name: "api")
        #expect(repository.id == "acme/api")
        #expect(repository.url == URL(string: "https://github.com/acme/api"))
    }

    @Test func matchingIgnoresCase() {
        let repository = WatchedRepository(owner: "Acme", name: "API")
        #expect(repository.matches("acme/api"))
        #expect(!repository.matches("acme/web"))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter WatchedRepositoryTests`
Expected: FAIL to compile with "cannot find 'WatchedRepository' in scope".

- [ ] **Step 3: Implement**

Create `Sources/Contour/Models/WatchedRepository.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter WatchedRepositoryTests`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add Sources/Contour/Models/WatchedRepository.swift Tests/ContourTests/WatchedRepositoryTests.swift
git commit -m "Parse and validate the repository a user asks to watch

Accepts owner/repo, a repository URL or a pull request URL. Owner and
name are held to GitHub's character set and an owner cannot start with
a hyphen, so the value is safe to pass to gh as an argument and to put
in a REST path."
```

### Task 7: Parse pull request lists and filter bots

**Files:**
- Create: `Sources/Contour/Services/WatchedPullRequests.swift`
- Create: `Tests/ContourTests/Fixtures/gh-pr-list.json`
- Create: `Tests/ContourTests/Fixtures/rest-pulls.json`
- Modify: `Tests/ContourTests/Fixtures/README.md`
- Create: `Tests/ContourTests/WatchedPullRequestsParseTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct WatchedPullRequest: Equatable, Identifiable, Sendable` with `url: String`, `number: Int`, `title: String`, `author: String`, `isDraft: Bool`, `createdAt: Date?`, `id: String` (the URL)
  - `struct WatchedPullRequestList: Equatable, Sendable` with `pullRequests: [WatchedPullRequest]`, `hasMore: Bool`, `fetchedAt: Date`
  - `struct WatchedPullRequests: Sendable` with:
    - `struct Candidate: Equatable, Sendable { var pullRequest: WatchedPullRequest; var isBot: Bool }`
    - `static let fetchLimit = 30`, `static let listLimit = 10`
    - `static func isBot(login: String, flagged: Bool) -> Bool`
    - `static func parseGH(_ data: Data) -> [Candidate]?`
    - `static func parseREST(_ data: Data) -> [Candidate]?`
    - `static func list(from candidates: [Candidate], fetchedAt: Date) -> WatchedPullRequestList`

- [ ] **Step 1: Capture the fixtures**

Both come from a public repository that always has bot pull requests open. Run from the repository root:

```sh
gh pr list -R cli/cli --state open --limit 30 \
  --json number,title,url,author,isDraft,createdAt \
  > Tests/ContourTests/Fixtures/gh-pr-list.json

curl -s -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/cli/cli/pulls?state=open&sort=created&direction=desc&per_page=30" \
  | jq '[.[] | {number, title, html_url, draft, created_at, user: {login: .user.login, type: .user.type}}]' \
  > Tests/ContourTests/Fixtures/rest-pulls.json
```

Check both captured a bot, or the fixture tests below cannot pass:

```sh
jq '[.[] | select(.author.is_bot)] | length' Tests/ContourTests/Fixtures/gh-pr-list.json
jq '[.[] | select(.user.type == "Bot")] | length' Tests/ContourTests/Fixtures/rest-pulls.json
```

Expected: both print a number greater than 0. If either prints 0, capture from `facebook/react` instead and use that name in the README entry.

- [ ] **Step 2: Record provenance**

Append to `Tests/ContourTests/Fixtures/README.md`, filling in the capture date:

```markdown
## `gh-pr-list.json`
Real output of `gh pr list -R cli/cli --state open --limit 30 --json
number,title,url,author,isDraft,createdAt`, captured 2026-09-29 and unedited. It holds
pull requests from people and from bots; `gh` spells a bot's login `app/dependabot` and
sets `author.is_bot`. `WatchedPullRequestsParseTests` relies on at least one bot being
present.

## `rest-pulls.json`
Real output of `GET /repos/cli/cli/pulls?state=open&sort=created&direction=desc&per_page=30`
from the anonymous REST API, captured 2026-09-29. The response was projected with `jq` to
the six fields the parser reads (`number`, `title`, `html_url`, `draft`, `created_at`,
`user.login`, `user.type`), because the full response is several hundred kilobytes of
fields nothing reads. No value was changed. The REST API spells a bot's login
`dependabot[bot]` and sets `user.type` to `Bot`.
```

- [ ] **Step 3: Write the failing tests**

Create `Tests/ContourTests/WatchedPullRequestsParseTests.swift`:

```swift
import Foundation
import Testing

@testable import Contour

struct WatchedPullRequestsParseTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func candidate(
        _ number: Int, author: String = "mwright", isBot: Bool = false, createdAt: TimeInterval? = nil
    ) -> WatchedPullRequests.Candidate {
        WatchedPullRequests.Candidate(
            pullRequest: WatchedPullRequest(
                url: "https://github.com/acme/api/pull/\(number)", number: number, title: "t\(number)",
                author: author, isDraft: false,
                createdAt: Date(timeIntervalSince1970: createdAt ?? TimeInterval(number))),
            isBot: isBot)
    }

    private let moment = Date(timeIntervalSince1970: 1_000_000)

    @Test func theGHFixtureParsesEveryRowAndFlagsItsBots() throws {
        let candidates = try #require(WatchedPullRequests.parseGH(try fixture("gh-pr-list")))
        #expect(!candidates.isEmpty)
        #expect(candidates.count <= WatchedPullRequests.fetchLimit)
        #expect(candidates.contains { $0.isBot })
        #expect(candidates.allSatisfy { $0.pullRequest.url.hasPrefix("https://github.com/") })
        #expect(candidates.allSatisfy { $0.pullRequest.createdAt != nil })
    }

    @Test func theRESTFixtureParsesEveryRowAndFlagsItsBots() throws {
        let candidates = try #require(WatchedPullRequests.parseREST(try fixture("rest-pulls")))
        #expect(!candidates.isEmpty)
        #expect(candidates.count <= WatchedPullRequests.fetchLimit)
        #expect(candidates.contains { $0.isBot })
        #expect(candidates.allSatisfy { $0.pullRequest.url.hasPrefix("https://github.com/") })
        #expect(candidates.allSatisfy { $0.pullRequest.createdAt != nil })
    }

    @Test func aListBuiltFromEitherFixtureHasNoBotsAndIsNewestFirst() throws {
        let sets = [
            try #require(WatchedPullRequests.parseGH(try fixture("gh-pr-list"))),
            try #require(WatchedPullRequests.parseREST(try fixture("rest-pulls"))),
        ]
        for candidates in sets {
            let list = WatchedPullRequests.list(from: candidates, fetchedAt: moment)
            let bots = Set(candidates.filter(\.isBot).map(\.pullRequest.url))
            #expect(list.pullRequests.count <= WatchedPullRequests.listLimit)
            #expect(list.pullRequests.allSatisfy { !bots.contains($0.url) })
            let dates = list.pullRequests.compactMap(\.createdAt)
            #expect(dates == dates.sorted(by: >))
            #expect(list.fetchedAt == moment)
        }
    }

    @Test func ghRowsCarryAuthorDraftAndDate() throws {
        let json = """
            [{"number":7,"title":"Seven","url":"https://github.com/acme/api/pull/7",
              "author":{"login":"mwright","is_bot":false},"isDraft":true,"createdAt":"2026-09-25T10:00:00Z"}]
            """
        let candidates = try #require(WatchedPullRequests.parseGH(Data(json.utf8)))
        #expect(
            candidates == [
                WatchedPullRequests.Candidate(
                    pullRequest: WatchedPullRequest(
                        url: "https://github.com/acme/api/pull/7", number: 7, title: "Seven", author: "mwright",
                        isDraft: true, createdAt: ISO8601DateFormatter().date(from: "2026-09-25T10:00:00Z")),
                    isBot: false)
            ])
    }

    @Test func restRowsCarryAuthorDraftAndDate() throws {
        let json = """
            [{"number":7,"title":"Seven","html_url":"https://github.com/acme/api/pull/7",
              "user":{"login":"mwright","type":"User"},"draft":true,"created_at":"2026-09-25T10:00:00Z"}]
            """
        let candidates = try #require(WatchedPullRequests.parseREST(Data(json.utf8)))
        #expect(
            candidates == [
                WatchedPullRequests.Candidate(
                    pullRequest: WatchedPullRequest(
                        url: "https://github.com/acme/api/pull/7", number: 7, title: "Seven", author: "mwright",
                        isDraft: true, createdAt: ISO8601DateFormatter().date(from: "2026-09-25T10:00:00Z")),
                    isBot: false)
            ])
    }

    @Test func rowsMissingOptionalFieldsStillParse() throws {
        let gh = #"[{"number":1,"title":"t","url":"https://github.com/acme/api/pull/1"}]"#
        let rest = #"[{"number":1,"title":"t","html_url":"https://github.com/acme/api/pull/1"}]"#
        for candidates in [
            try #require(WatchedPullRequests.parseGH(Data(gh.utf8))),
            try #require(WatchedPullRequests.parseREST(Data(rest.utf8))),
        ] {
            #expect(candidates.count == 1)
            #expect(candidates[0].pullRequest.author == "unknown")
            #expect(candidates[0].pullRequest.isDraft == false)
            #expect(candidates[0].pullRequest.createdAt == nil)
            #expect(candidates[0].isBot == false)
        }
    }

    @Test func rowsMissingRequiredFieldsAreDropped() throws {
        let gh = #"[{"title":"no number","url":"u"},{"number":2,"url":"u"},{"number":3,"title":"no url"}]"#
        let rest = #"[{"title":"no number","html_url":"u"},{"number":2,"html_url":"u"},{"number":3,"title":"x"}]"#
        #expect(try #require(WatchedPullRequests.parseGH(Data(gh.utf8))).isEmpty)
        #expect(try #require(WatchedPullRequests.parseREST(Data(rest.utf8))).isEmpty)
    }

    @Test func anEmptyArrayIsAnEmptyListNotAFailure() throws {
        #expect(try #require(WatchedPullRequests.parseGH(Data("[]".utf8))).isEmpty)
        #expect(try #require(WatchedPullRequests.parseREST(Data("[]".utf8))).isEmpty)
    }

    @Test(arguments: ["", "not json", "{}", #"{"message":"Not Found"}"#, "[1,2]"])
    func inputThatIsNotAListOfObjectsCannotBeRead(input: String) {
        #expect(WatchedPullRequests.parseGH(Data(input.utf8)) == nil)
        #expect(WatchedPullRequests.parseREST(Data(input.utf8)) == nil)
    }

    @Test func botsAreRecognisedByFlagByAppPrefixAndByBotSuffix() {
        #expect(WatchedPullRequests.isBot(login: "someone", flagged: true))
        #expect(WatchedPullRequests.isBot(login: "app/dependabot", flagged: false))
        #expect(WatchedPullRequests.isBot(login: "renovate[bot]", flagged: false))
        #expect(!WatchedPullRequests.isBot(login: "mwright", flagged: false))
        #expect(!WatchedPullRequests.isBot(login: "application", flagged: false))
    }

    @Test func bothTransportsFlagABotFromItsLoginAlone() throws {
        let gh = #"[{"number":1,"title":"t","url":"u","author":{"login":"app/renovate"}}]"#
        let rest = #"[{"number":1,"title":"t","html_url":"u","user":{"login":"renovate[bot]"}}]"#
        #expect(try #require(WatchedPullRequests.parseGH(Data(gh.utf8)))[0].isBot)
        #expect(try #require(WatchedPullRequests.parseREST(Data(rest.utf8)))[0].isBot)
    }

    @Test func aListDropsBotsSortsNewestFirstAndKeepsTen() {
        let people = (1...12).map { candidate($0) }
        let bots = (13...15).map { candidate($0, author: "app/dependabot", isBot: true) }
        let list = WatchedPullRequests.list(from: (people + bots).shuffled(), fetchedAt: moment)
        #expect(list.pullRequests.map(\.number) == [12, 11, 10, 9, 8, 7, 6, 5, 4, 3])
        #expect(list.hasMore)
    }

    @Test func rowsWithoutADateSortLast() {
        var undated = candidate(99)
        undated.pullRequest.createdAt = nil
        let list = WatchedPullRequests.list(from: [undated, candidate(1), candidate(2)], fetchedAt: moment)
        #expect(list.pullRequests.map(\.number) == [2, 1, 99])
    }

    @Test func aShortListHasNoMore() {
        let list = WatchedPullRequests.list(from: (1...10).map { candidate($0) }, fetchedAt: moment)
        #expect(list.pullRequests.count == 10)
        #expect(!list.hasMore)
    }

    @Test func aFullPageMeansThereMayBeMoreEvenWithFewPeople() {
        let people = (1...4).map { candidate($0) }
        let bots = (5...30).map { candidate($0, author: "app/dependabot", isBot: true) }
        let list = WatchedPullRequests.list(from: people + bots, fetchedAt: moment)
        #expect(list.pullRequests.count == 4)
        #expect(list.hasMore)
    }

    @Test func aFullPageOfBotsLeavesAnEmptyListThatHasMore() {
        let bots = (1...30).map { candidate($0, author: "app/dependabot", isBot: true) }
        let list = WatchedPullRequests.list(from: bots, fetchedAt: moment)
        #expect(list.pullRequests.isEmpty)
        #expect(list.hasMore)
    }

    @Test func aPullRequestIsIdentifiedByItsURL() {
        #expect(candidate(7).pullRequest.id == "https://github.com/acme/api/pull/7")
    }
}
```

- [ ] **Step 4: Run to verify they fail**

Run: `swift test --filter WatchedPullRequestsParseTests`
Expected: FAIL to compile with "cannot find 'WatchedPullRequests' in scope".

- [ ] **Step 5: Implement**

Create `Sources/Contour/Services/WatchedPullRequests.swift`:

```swift
import Foundation

struct WatchedPullRequest: Equatable, Identifiable, Sendable {
    var url: String
    var number: Int
    var title: String
    var author: String
    var isDraft: Bool
    var createdAt: Date?

    var id: String { url }
}

struct WatchedPullRequestList: Equatable, Sendable {
    var pullRequests: [WatchedPullRequest]
    var hasMore: Bool
    var fetchedAt: Date
}

struct WatchedPullRequests: Sendable {
    struct Candidate: Equatable, Sendable {
        var pullRequest: WatchedPullRequest
        var isBot: Bool
    }

    static let fetchLimit = 30
    static let listLimit = 10

    static func isBot(login: String, flagged: Bool) -> Bool {
        flagged || login.hasPrefix("app/") || login.hasSuffix("[bot]")
    }

    static func parseGH(_ data: Data) -> [Candidate]? {
        parse(data, url: "url", draft: "isDraft", createdAt: "createdAt", author: "author") { author in
            (author["is_bot"] as? Bool) ?? false
        }
    }

    static func parseREST(_ data: Data) -> [Candidate]? {
        parse(data, url: "html_url", draft: "draft", createdAt: "created_at", author: "user") { author in
            (author["type"] as? String) == "Bot"
        }
    }

    static func list(from candidates: [Candidate], fetchedAt: Date) -> WatchedPullRequestList {
        let people = candidates.filter { !$0.isBot }.map(\.pullRequest)
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return WatchedPullRequestList(
            pullRequests: Array(people.prefix(listLimit)),
            hasMore: people.count > listLimit || candidates.count >= fetchLimit,
            fetchedAt: fetchedAt)
    }

    private static func parse(
        _ data: Data, url: String, draft: String, createdAt: String, author: String,
        flagged: ([String: Any]) -> Bool
    ) -> [Candidate]? {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        let dates = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let link = row[url] as? String,
                let number = row["number"] as? Int,
                let title = row["title"] as? String
            else { return nil }
            let person = (row[author] as? [String: Any]) ?? [:]
            let login = (person["login"] as? String) ?? "unknown"
            return Candidate(
                pullRequest: WatchedPullRequest(
                    url: link, number: number, title: title, author: login,
                    isDraft: (row[draft] as? Bool) ?? false,
                    createdAt: (row[createdAt] as? String).flatMap(dates.date(from:))),
                isBot: isBot(login: login, flagged: flagged(person)))
        }
    }
}
```

- [ ] **Step 6: Run to verify they pass**

Run: `swift test --filter WatchedPullRequestsParseTests`
Expected: PASS.

- [ ] **Step 7: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add Sources/Contour/Services/WatchedPullRequests.swift Tests/ContourTests
git commit -m "Parse a repository's open pull requests and leave out bots

gh and the REST API name the same fields differently and spell a bot's
login differently (app/dependabot, dependabot[bot]), so each has its own
parser over a shared row reader. Thirty are fetched so that removing
bots still leaves ten."
```

### Task 8: Fetch over gh or the anonymous API, and say what went wrong

**Files:**
- Modify: `Sources/Contour/Services/WatchedPullRequests.swift`
- Modify: `Sources/Contour/Services/AnonymousAPISource.swift`
- Create: `Tests/ContourTests/WatchedPullRequestsFetchTests.swift`

**Interfaces:**
- Consumes: `WatchedRepository` (Task 6); `parseGH`, `parseREST`, `list(from:fetchedAt:)` (Task 7); `GitHubAccessMode`; `Shell.run`, `Shell.which`; `ProcessError`; `GitHubServiceError`; `AnonymousAPISource(session:)`.
- Produces:
  - `enum WatchedFailure: Error, Equatable, Sendable` with `.notFound`, `.rateLimited(resetAt: Date?)`, `.unavailable`
  - `WatchedPullRequests.init(ghAvailable:runGH:anonymous:now:)`, every parameter defaulted
  - `func fetch(_ repository: WatchedRepository, access: GitHubAccessMode) async -> Result<WatchedPullRequestList, WatchedFailure>`
  - `func viewerLogin(access: GitHubAccessMode) async -> String?`
  - `enum WatchedPullRequests.Transport { case gh, rest }`
  - `static func transport(access: GitHubAccessMode, ghAvailable: Bool) -> Transport?`
  - `static func arguments(for repository: WatchedRepository) -> [String]`
  - `static func failure(from error: any Error) -> WatchedFailure`
  - `static func message(for failure: WatchedFailure, repository: String, anonymous: Bool) -> String`
  - `AnonymousAPISource.openPullRequests(owner: String, repo: String, limit: Int) async throws -> Data`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ContourTests/WatchedPullRequestsFetchTests.swift`. The REST tests extend `AnonymousAPISourceTests` because `MockURLProtocol` has one process-wide handler, and that suite is already serialized around it:

```swift
import Foundation
import Testing
import os

@testable import Contour

struct WatchedPullRequestsFetchTests {
    private let repository = WatchedRepository(owner: "acme", name: "api")
    private let moment = Date(timeIntervalSince1970: 1_000_000)

    private let oneRow = """
        [{"number":7,"title":"Seven","url":"https://github.com/acme/api/pull/7",
          "author":{"login":"mwright","is_bot":false},"isDraft":false,"createdAt":"2026-09-25T10:00:00Z"}]
        """

    private func service(
        ghAvailable: Bool = true, runGH: @escaping @Sendable ([String]) async throws -> String
    ) -> WatchedPullRequests {
        let moment = moment
        return WatchedPullRequests(ghAvailable: { ghAvailable }, runGH: runGH, now: { moment })
    }

    @Test func transportFollowsTheAccessModeAndWhetherGHIsInstalled() {
        #expect(WatchedPullRequests.transport(access: .anonymous, ghAvailable: true) == .rest)
        #expect(WatchedPullRequests.transport(access: .anonymous, ghAvailable: false) == .rest)
        #expect(WatchedPullRequests.transport(access: .gh, ghAvailable: true) == .gh)
        #expect(WatchedPullRequests.transport(access: .gh, ghAvailable: false) == nil)
        #expect(WatchedPullRequests.transport(access: .auto, ghAvailable: true) == .gh)
        #expect(WatchedPullRequests.transport(access: .auto, ghAvailable: false) == .rest)
    }

    @Test func ghIsAskedForThirtyOpenPullRequestsInTheRepository() {
        #expect(
            WatchedPullRequests.arguments(for: repository) == [
                "pr", "list", "-R", "acme/api", "--state", "open", "--limit", "30",
                "--json", "number,title,url,author,isDraft,createdAt",
            ])
    }

    @Test func aGHAnswerBecomesAListStampedWithTheFetchTime() async {
        let seen = OSAllocatedUnfairLock<[[String]]>(initialState: [])
        let oneRow = oneRow
        let service = service { arguments in
            seen.withLock { $0.append(arguments) }
            return oneRow
        }
        let result = await service.fetch(repository, access: .gh)
        #expect(seen.withLock { $0 } == [WatchedPullRequests.arguments(for: repository)])
        #expect((try? result.get())?.pullRequests.map(\.number) == [7])
        #expect((try? result.get())?.fetchedAt == moment)
    }

    @Test func ghAccessWithoutGHInstalledIsUnavailableAndRunsNothing() async {
        let service = service(ghAvailable: false) { _ in
            Issue.record("gh must not run")
            return ""
        }
        #expect(await service.fetch(repository, access: .gh) == .failure(.unavailable))
    }

    @Test func aGHAnswerThatIsNotAListIsUnavailable() async {
        let service = service { _ in "not json" }
        #expect(await service.fetch(repository, access: .gh) == .failure(.unavailable))
    }

    @Test func ghNotFindingTheRepositoryIsNotFound() async {
        let service = service { _ in
            throw ProcessError(
                command: "gh pr list", exitCode: 1,
                stderr: "GraphQL: Could not resolve to a Repository with the name 'acme/api'. (repository)")
        }
        #expect(await service.fetch(repository, access: .gh) == .failure(.notFound))
    }

    @Test func ghHittingTheRateLimitIsRateLimited() async {
        let service = service { _ in
            throw ProcessError(command: "gh pr list", exitCode: 1, stderr: "HTTP 403: API rate limit exceeded")
        }
        #expect(await service.fetch(repository, access: .gh) == .failure(.rateLimited(resetAt: nil)))
    }

    @Test func anyOtherGHFailureIsUnavailable() async {
        let service = service { _ in
            throw ProcessError(command: "gh pr list", exitCode: 4, stderr: "gh auth login")
        }
        #expect(await service.fetch(repository, access: .gh) == .failure(.unavailable))
    }

    @Test func serviceErrorsMapOntoFailures() {
        let reset = Date(timeIntervalSince1970: 5)
        #expect(
            WatchedPullRequests.failure(from: GitHubServiceError.privateRepository(owner: "a", repo: "b"))
                == .notFound)
        #expect(
            WatchedPullRequests.failure(from: GitHubServiceError.rateLimited(resetAt: reset))
                == .rateLimited(resetAt: reset))
        #expect(WatchedPullRequests.failure(from: GitHubServiceError.ghUnavailable) == .unavailable)
        #expect(WatchedPullRequests.failure(from: CancellationError()) == .unavailable)
    }

    @Test func theViewerLoginComesFromGHAndIsTrimmed() async {
        let seen = OSAllocatedUnfairLock<[[String]]>(initialState: [])
        let service = service { arguments in
            seen.withLock { $0.append(arguments) }
            return "jstephens\n"
        }
        #expect(await service.viewerLogin(access: .auto) == "jstephens")
        #expect(seen.withLock { $0 } == [["api", "user", "--jq", ".login"]])
    }

    @Test func thereIsNoViewerLoginAnonymouslyOrWhenGHFailsOrAnswersNothing() async {
        let never = service { _ in
            Issue.record("gh must not run")
            return ""
        }
        #expect(await never.viewerLogin(access: .anonymous) == nil)

        let failing = service { _ in throw ProcessError(command: "gh api user", exitCode: 1, stderr: "no") }
        #expect(await failing.viewerLogin(access: .gh) == nil)

        let blank = service { _ in "\n" }
        #expect(await blank.viewerLogin(access: .gh) == nil)
    }

    @Test func aMissingRepositoryIsExplainedAndAnonymousAccessIsToldHowToSignIn() {
        #expect(
            WatchedPullRequests.message(for: .notFound, repository: "acme/api", anonymous: true)
                == "Couldn't list pull requests for acme/api. It's private or doesn't exist. "
                + "Sign in with the GitHub CLI to watch private repositories.")
        #expect(
            WatchedPullRequests.message(for: .notFound, repository: "acme/api", anonymous: false)
                == "Couldn't list pull requests for acme/api. It's private or doesn't exist.")
    }

    @Test func aRateLimitNamesWhenToTryAgainIfGitHubSaid() {
        let reset = Date(timeIntervalSince1970: 1_000_000)
        let time = DateFormatter.localizedString(from: reset, dateStyle: .none, timeStyle: .short)
        #expect(
            WatchedPullRequests.message(
                for: .rateLimited(resetAt: reset), repository: "acme/api", anonymous: true)
                == "Couldn't list pull requests for acme/api. GitHub's anonymous limit is used up. "
                + "Try again after \(time).")
        #expect(
            WatchedPullRequests.message(for: .rateLimited(resetAt: nil), repository: "acme/api", anonymous: false)
                == "Couldn't list pull requests for acme/api. GitHub's rate limit is used up.")
    }

    @Test func anyOtherFailureSaysOnlyWhatCouldNotBeDone() {
        #expect(
            WatchedPullRequests.message(for: .unavailable, repository: "acme/api", anonymous: true)
                == "Couldn't list pull requests for acme/api.")
    }
}

extension AnonymousAPISourceTests {
    private func watchedService() -> WatchedPullRequests {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return WatchedPullRequests(
            ghAvailable: { false },
            runGH: { _ in
                Issue.record("gh must not run")
                return ""
            },
            anonymous: AnonymousAPISource(session: URLSession(configuration: config)),
            now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    private var watchedRepository: WatchedRepository { WatchedRepository(owner: "acme", name: "api") }

    @Test func watchedPullRequestsAreReadFromTheOpenPullsEndpoint() async {
        let seen = OSAllocatedUnfairLock<[String]>(initialState: [])
        MockURLProtocol.handler = { request in
            seen.withLock { $0.append(request.url?.absoluteString ?? "") }
            let body = """
                [{"number":7,"title":"Seven","html_url":"https://github.com/acme/api/pull/7",
                  "user":{"login":"mwright","type":"User"},"draft":false,"created_at":"2026-09-25T10:00:00Z"},
                 {"number":8,"title":"Bump","html_url":"https://github.com/acme/api/pull/8",
                  "user":{"login":"dependabot[bot]","type":"Bot"},"draft":false,
                  "created_at":"2026-09-26T10:00:00Z"}]
                """
            return MockURLProtocol.Canned(status: 200, body: Data(body.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let result = await watchedService().fetch(watchedRepository, access: .auto)
        #expect((try? result.get())?.pullRequests.map(\.number) == [7])
        #expect(
            seen.withLock { $0 } == [
                "https://api.github.com/repos/acme/api/pulls?state=open&sort=created&direction=desc&per_page=30"
            ])
    }

    @Test func aMissingWatchedRepositoryIsNotFound() async {
        MockURLProtocol.handler = { _ in MockURLProtocol.Canned(status: 404, body: Data("{}".utf8)) }
        defer { MockURLProtocol.handler = nil }
        #expect(await watchedService().fetch(watchedRepository, access: .anonymous) == .failure(.notFound))
    }

    @Test func anExhaustedAnonymousLimitCarriesItsResetTime() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Canned(
                status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1700000000"],
                body: Data("{}".utf8))
        }
        defer { MockURLProtocol.handler = nil }
        #expect(
            await watchedService().fetch(watchedRepository, access: .anonymous)
                == .failure(.rateLimited(resetAt: Date(timeIntervalSince1970: 1_700_000_000))))
    }

    @Test func aWatchedAnswerThatIsNotAListIsUnavailable() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Canned(status: 200, body: Data(#"{"message":"odd"}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }
        #expect(await watchedService().fetch(watchedRepository, access: .anonymous) == .failure(.unavailable))
    }

    @Test func aServerErrorForAWatchedRepositoryIsUnavailable() async {
        MockURLProtocol.handler = { _ in MockURLProtocol.Canned(status: 500, body: Data("boom".utf8)) }
        defer { MockURLProtocol.handler = nil }
        #expect(await watchedService().fetch(watchedRepository, access: .anonymous) == .failure(.unavailable))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter WatchedPullRequestsFetchTests`
Expected: FAIL to compile with "cannot find 'WatchedFailure' in scope".

- [ ] **Step 3: Add the REST call to AnonymousAPISource**

In `AnonymousAPISource.swift`, after `fetchIssue`:

```swift
    func openPullRequests(owner: String, repo: String, limit: Int) async throws -> Data {
        let path = "/repos/\(owner)/\(repo)/pulls?state=open&sort=created&direction=desc&per_page=\(limit)"
        let (data, _) = try await send(
            request(path, accept: "application/vnd.github+json"), owner: owner, repo: repo)
        return data
    }
```

- [ ] **Step 4: Implement fetching and failure text**

In `WatchedPullRequests.swift`, add `import os` at the top, add before `struct WatchedPullRequests`:

```swift
enum WatchedFailure: Error, Equatable, Sendable {
    case notFound
    case rateLimited(resetAt: Date?)
    case unavailable
}

private let watchedLogger = Logger(subsystem: "Contour", category: "WatchedPullRequests")
```

and add inside `struct WatchedPullRequests`, above the static members:

```swift
    enum Transport: Equatable, Sendable {
        case gh
        case rest
    }

    var ghAvailable: @Sendable () -> Bool = { Shell.which("gh") != nil }
    var runGH: @Sendable ([String]) async throws -> String = { try await Shell.run("gh", $0) }
    var anonymous = AnonymousAPISource()
    var now: @Sendable () -> Date = { Date() }

    func fetch(
        _ repository: WatchedRepository, access: GitHubAccessMode
    ) async -> Result<WatchedPullRequestList, WatchedFailure> {
        guard let transport = Self.transport(access: access, ghAvailable: ghAvailable()) else {
            return .failure(.unavailable)
        }
        do {
            let candidates: [Candidate]?
            switch transport {
            case .gh:
                candidates = Self.parseGH(Data(try await runGH(Self.arguments(for: repository)).utf8))
            case .rest:
                candidates = Self.parseREST(
                    try await anonymous.openPullRequests(
                        owner: repository.owner, repo: repository.name, limit: Self.fetchLimit))
            }
            guard let candidates else {
                watchedLogger.error("Unreadable pull request list for \(repository.id, privacy: .public)")
                return .failure(.unavailable)
            }
            return .success(Self.list(from: candidates, fetchedAt: now()))
        } catch {
            watchedLogger.error(
                "Listing \(repository.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return .failure(Self.failure(from: error))
        }
    }

    func viewerLogin(access: GitHubAccessMode) async -> String? {
        guard Self.transport(access: access, ghAvailable: ghAvailable()) == .gh,
            let output = try? await runGH(["api", "user", "--jq", ".login"])
        else { return nil }
        let login = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : login
    }

    static func transport(access: GitHubAccessMode, ghAvailable: Bool) -> Transport? {
        switch access {
        case .anonymous: return .rest
        case .gh: return ghAvailable ? .gh : nil
        case .auto: return ghAvailable ? .gh : .rest
        }
    }

    static func arguments(for repository: WatchedRepository) -> [String] {
        [
            "pr", "list", "-R", repository.id, "--state", "open", "--limit", String(fetchLimit),
            "--json", "number,title,url,author,isDraft,createdAt",
        ]
    }

    static func failure(from error: any Error) -> WatchedFailure {
        switch error {
        case let process as ProcessError:
            if process.stderr.contains("Could not resolve to a Repository") { return .notFound }
            if process.stderr.localizedCaseInsensitiveContains("rate limit") { return .rateLimited(resetAt: nil) }
            return .unavailable
        case GitHubServiceError.privateRepository:
            return .notFound
        case GitHubServiceError.rateLimited(let resetAt):
            return .rateLimited(resetAt: resetAt)
        default:
            return .unavailable
        }
    }

    static func message(for failure: WatchedFailure, repository: String, anonymous: Bool) -> String {
        let lead = "Couldn't list pull requests for \(repository)."
        switch failure {
        case .notFound:
            let signIn = anonymous ? " Sign in with the GitHub CLI to watch private repositories." : ""
            return "\(lead) It's private or doesn't exist.\(signIn)"
        case .rateLimited(let resetAt):
            let limit = anonymous ? "GitHub's anonymous limit is used up." : "GitHub's rate limit is used up."
            let when =
                resetAt.map {
                    " Try again after \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))."
                } ?? ""
            return "\(lead) \(limit)\(when)"
        case .unavailable:
            return lead
        }
    }
```

- [ ] **Step 5: Run to verify they pass**

Run: `swift test --filter WatchedPullRequestsFetchTests && swift test --filter AnonymousAPISourceTests`
Expected: PASS.

- [ ] **Step 6: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add Sources/Contour/Services Tests/ContourTests/WatchedPullRequestsFetchTests.swift
git commit -m "Fetch a watched repository's pull requests over gh or the REST API

The transport follows the GitHub access setting as PR fetching does.
Failures reduce to three the reviewer can act on: the repository can't
be seen, the rate limit is spent, or something else went wrong. Raw
stderr and response bodies go to the log."
```

### Task 9: Watching in the model

**Files:**
- Modify: `Sources/Contour/Services/Preferences.swift`
- Modify: `Sources/Contour/Views/Start/StartScreenLogic.swift`
- Modify: `Sources/Contour/Views/Start/StartScreenModel.swift`
- Modify: `Tests/ContourTests/PreferencesTests.swift`
- Modify: `Tests/ContourTests/StartScreenLogicTests.swift`
- Create: `Tests/ContourTests/StartScreenModelWatchingTests.swift`

**Interfaces:**
- Consumes: `WatchedRepository` (Task 6); `WatchedPullRequest`, `WatchedPullRequestList`, `WatchedPullRequests.fetchLimit` (Task 7); `WatchedFailure`, `WatchedPullRequests.fetch`, `.viewerLogin`, `.transport`, `.message` (Task 8).
- Produces:
  - `Preferences.watchedRepositories: [WatchedRepository]`
  - `enum WatchedLoadState: Equatable, Sendable` with `.loading`, `.loaded(WatchedPullRequestList)`, `.failed(WatchedFailure, keeping: WatchedPullRequestList?)`, `var list: WatchedPullRequestList?`, `var failure: WatchedFailure?`
  - `StartScreenLogic`: `freshForGH`, `freshAnonymously`, `isFresh(lastAttempt:now:anonymous:)`, `state(after:previous:)`, `count(_ state: WatchedLoadState?)`, `labels(for:repository:viewerLogin:reviewRequests:)`, `suggestions(recents:watched:limit:)`, `canWatch(_:)`, `emptyMessage(for list: WatchedPullRequestList)`, `fetchedLabel(_:)`
  - `StartScreenModel.Dependencies` gains `fetchWatched`, `loadViewerLogin`, `usesAnonymousAccess`, `now`, all defaulted
  - `StartScreenModel`: `var watched: [WatchedRepository]`, `var viewerLogin: String?`, `var suggestions: [String]`, `func state(for id: String) -> WatchedLoadState?`, `func isWatched(_ id: String?) -> Bool`, `func watch(_ input: String) async -> Bool`, `func stopWatching(_ id: String)`, `func toggleWatch(_ id: String) async`, `func loadRemoteSources() async` (replaces the Part 1 `reload()`, which no longer exists: it loads review requests, the viewer login once, and stale watched lists concurrently; every write after an await is skipped when the task was cancelled), `func refresh(_ id: String) async`, `func refreshWatched(force: Bool) async`, `func labels(for pullRequest: WatchedPullRequest, in repository: String) -> [String]`, `func failureMessage(for failure: WatchedFailure, repository: String) -> String`

- [ ] **Step 1: Write the failing Preferences tests**

Append to `PreferencesTests`:

```swift
    @Test func watchedRepositoriesRoundTripInOrderAndDefaultToNone() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults, environment: [:])
        #expect(prefs.watchedRepositories.isEmpty)
        prefs.watchedRepositories = [
            WatchedRepository(owner: "acme", name: "web"), WatchedRepository(owner: "acme", name: "api"),
        ]
        #expect(
            Preferences(defaults: defaults, environment: [:]).watchedRepositories.map(\.id)
                == ["acme/web", "acme/api"])
    }

    @Test func storedWatchedRepositoriesThatAreNotValidAreDropped() {
        let defaults = freshDefaults()
        defaults.set(["acme/api", "--flag/x", "", "https://gitlab.com/a/b", "acme/web"], forKey: "watchedRepositories")
        #expect(
            Preferences(defaults: defaults, environment: [:]).watchedRepositories.map(\.id)
                == ["acme/api", "acme/web"])
    }
```

- [ ] **Step 2: Run to verify they fail, then implement**

Run: `swift test --filter PreferencesTests/watchedRepositoriesRoundTripInOrderAndDefaultToNone`
Expected: FAIL to compile with "value of type 'Preferences' has no member 'watchedRepositories'".

In `Preferences.swift`, add to `private enum Key`:

```swift
        static let watchedRepositories = "watchedRepositories"
```

and after `lastStartSource`:

```swift
    var watchedRepositories: [WatchedRepository] {
        get { (defaults.stringArray(forKey: Key.watchedRepositories) ?? []).compactMap(WatchedRepository.parse) }
        set { defaults.set(newValue.map(\.id), forKey: Key.watchedRepositories) }
    }
```

Run: `swift test --filter PreferencesTests`
Expected: PASS.

- [ ] **Step 3: Write the failing logic tests**

Append to `StartScreenLogicTests`:

```swift
    private func pullRequest(_ number: Int, author: String = "mwright", isDraft: Bool = false) -> WatchedPullRequest {
        WatchedPullRequest(
            url: "https://github.com/acme/api/pull/\(number)", number: number, title: "t\(number)",
            author: author, isDraft: isDraft, createdAt: Date(timeIntervalSince1970: TimeInterval(number)))
    }

    private func list(_ count: Int, hasMore: Bool = false) -> WatchedPullRequestList {
        WatchedPullRequestList(
            pullRequests: count == 0 ? [] : (1...count).map { pullRequest($0) }, hasMore: hasMore,
            fetchedAt: Date(timeIntervalSince1970: 1_000))
    }

    @Test func aListIsFreshForTwoMinutesUnderGHAndTenAnonymously() {
        let attempt = Date(timeIntervalSince1970: 1_000)
        #expect(StartScreenLogic.isFresh(lastAttempt: attempt, now: attempt + 119, anonymous: false))
        #expect(!StartScreenLogic.isFresh(lastAttempt: attempt, now: attempt + 120, anonymous: false))
        #expect(StartScreenLogic.isFresh(lastAttempt: attempt, now: attempt + 599, anonymous: true))
        #expect(!StartScreenLogic.isFresh(lastAttempt: attempt, now: attempt + 600, anonymous: true))
    }

    @Test func aRepositoryNeverFetchedIsNotFresh() {
        #expect(!StartScreenLogic.isFresh(lastAttempt: nil, now: Date(), anonymous: false))
    }

    @Test func aSuccessfulFetchReplacesWhateverWasThere() {
        #expect(StartScreenLogic.state(after: .success(list(2)), previous: .loading) == .loaded(list(2)))
        #expect(
            StartScreenLogic.state(after: .success(list(2)), previous: .failed(.notFound, keeping: nil))
                == .loaded(list(2)))
    }

    @Test func aFailedFetchKeepsTheRowsThatWereAlreadyShown() {
        #expect(
            StartScreenLogic.state(after: .failure(.unavailable), previous: .loaded(list(3)))
                == .failed(.unavailable, keeping: list(3)))
        #expect(
            StartScreenLogic.state(after: .failure(.notFound), previous: .failed(.unavailable, keeping: list(3)))
                == .failed(.notFound, keeping: list(3)))
        #expect(
            StartScreenLogic.state(after: .failure(.notFound), previous: .loading)
                == .failed(.notFound, keeping: nil))
        #expect(StartScreenLogic.state(after: .failure(.notFound), previous: nil) == .failed(.notFound, keeping: nil))
    }

    @Test func loadStatesExposeTheirListAndFailure() {
        #expect(WatchedLoadState.loading.list == nil)
        #expect(WatchedLoadState.loading.failure == nil)
        #expect(WatchedLoadState.loaded(list(1)).list == list(1))
        #expect(WatchedLoadState.loaded(list(1)).failure == nil)
        #expect(WatchedLoadState.failed(.notFound, keeping: list(1)).list == list(1))
        #expect(WatchedLoadState.failed(.notFound, keeping: nil).failure == .notFound)
    }

    @Test func aWatchedCountIsTheRowsListedWithAPlusWhenThereAreMore() {
        #expect(StartScreenLogic.count(WatchedLoadState?.none) == nil)
        #expect(StartScreenLogic.count(.loading) == nil)
        #expect(StartScreenLogic.count(.loaded(list(0))) == nil)
        #expect(StartScreenLogic.count(.loaded(list(7))) == "7")
        #expect(StartScreenLogic.count(.loaded(list(10, hasMore: true))) == "10+")
        #expect(StartScreenLogic.count(.loaded(list(4, hasMore: true))) == "4+")
        #expect(StartScreenLogic.count(.failed(.notFound, keeping: nil)) == "!")
        #expect(StartScreenLogic.count(.failed(.notFound, keeping: list(3))) == "!")
    }

    @Test func labelsMarkDraftsTheViewersOwnAndRequestedReviews() {
        let requested = ReviewRequest(
            url: "https://github.com/acme/api/pull/3", repo: "acme/api", number: 3, title: "t", author: "a",
            isDraft: false, updatedAt: nil)
        #expect(
            StartScreenLogic.labels(
                for: pullRequest(3, author: "jstephens", isDraft: true), repository: "acme/api",
                viewerLogin: "jstephens", reviewRequests: [requested])
                == ["draft", "yours", "review requested"])
        #expect(
            StartScreenLogic.labels(
                for: pullRequest(4), repository: "acme/api", viewerLogin: "jstephens", reviewRequests: [requested]
            ).isEmpty)
    }

    @Test func labelsCompareLoginsAndRepositoriesWithoutRegardToCase() {
        let requested = ReviewRequest(
            url: "u", repo: "Acme/API", number: 3, title: "t", author: "a", isDraft: false, updatedAt: nil)
        #expect(
            StartScreenLogic.labels(
                for: pullRequest(3, author: "JStephens"), repository: "acme/api", viewerLogin: "jstephens",
                reviewRequests: [requested])
                == ["yours", "review requested"])
    }

    @Test func nothingIsYoursWhenTheViewerIsUnknown() {
        #expect(
            StartScreenLogic.labels(
                for: pullRequest(3, author: "unknown"), repository: "acme/api", viewerLogin: nil,
                reviewRequests: []
            ).isEmpty)
    }

    @Test func aRequestForTheSameNumberInAnotherRepositoryDoesNotLabelTheRow() {
        let elsewhere = ReviewRequest(
            url: "u", repo: "acme/web", number: 3, title: "t", author: "a", isDraft: false, updatedAt: nil)
        #expect(
            StartScreenLogic.labels(
                for: pullRequest(3), repository: "acme/api", viewerLogin: nil, reviewRequests: [elsewhere]
            ).isEmpty)
    }

    @Test func suggestionsAreRecentRepositoriesNotYetWatchedMostRecentFirst() {
        let recents = [
            AnalysisCache.RecentPR(url: "u", repo: "acme/web", number: 1, title: "t", lastOpened: Date()),
            AnalysisCache.RecentPR(url: "u", repo: "acme/api", number: 2, title: "t", lastOpened: Date()),
            AnalysisCache.RecentPR(url: "u", repo: "acme/web", number: 3, title: "t", lastOpened: Date()),
            AnalysisCache.RecentPR(url: "u", repo: "acme/infra", number: 4, title: "t", lastOpened: Date()),
            AnalysisCache.RecentPR(url: "u", repo: "not a repo", number: 5, title: "t", lastOpened: Date()),
        ]
        #expect(
            StartScreenLogic.suggestions(
                recents: recents, watched: [WatchedRepository(owner: "Acme", name: "API")])
                == ["acme/web", "acme/infra"])
    }

    @Test func atMostFiveRepositoriesAreSuggested() {
        let recents = (1...8).map {
            AnalysisCache.RecentPR(url: "u", repo: "acme/r\($0)", number: $0, title: "t", lastOpened: Date())
        }
        #expect(
            StartScreenLogic.suggestions(recents: recents, watched: [])
                == ["acme/r1", "acme/r2", "acme/r3", "acme/r4", "acme/r5"])
        #expect(StartScreenLogic.suggestions(recents: recents, watched: [], limit: 2) == ["acme/r1", "acme/r2"])
    }

    @Test func onlyInputThatNamesARepositoryCanBeWatched() {
        #expect(StartScreenLogic.canWatch("acme/api"))
        #expect(StartScreenLogic.canWatch("https://github.com/acme/api/pull/3"))
        #expect(!StartScreenLogic.canWatch(""))
        #expect(!StartScreenLogic.canWatch("--flag/x"))
    }

    @Test func anEmptyListSaysSoUnlessBotsCrowdedEveryoneOut() {
        #expect(StartScreenLogic.emptyMessage(for: list(0)) == "No open pull requests.")
        #expect(
            StartScreenLogic.emptyMessage(for: list(0, hasMore: true))
                == "The newest 30 open pull requests are all automated.")
    }

    @Test func theFetchedLabelSaysWhenTheListWasUpdated() {
        #expect(StartScreenLogic.fetchedLabel(Date()).hasPrefix("updated "))
    }
```

- [ ] **Step 4: Run to verify they fail**

Run: `swift test --filter StartScreenLogicTests`
Expected: FAIL to compile with "cannot find 'WatchedLoadState' in scope".

- [ ] **Step 5: Implement the logic**

Add to `StartScreenLogic.swift`, above `enum StartScreenLogic`:

```swift
enum WatchedLoadState: Equatable, Sendable {
    case loading
    case loaded(WatchedPullRequestList)
    case failed(WatchedFailure, keeping: WatchedPullRequestList?)

    var list: WatchedPullRequestList? {
        switch self {
        case .loading: return nil
        case .loaded(let list): return list
        case .failed(_, let kept): return kept
        }
    }

    var failure: WatchedFailure? {
        if case .failed(let failure, _) = self { return failure }
        return nil
    }
}
```

and inside `enum StartScreenLogic`:

```swift
    static let freshForGH: TimeInterval = 120
    static let freshAnonymously: TimeInterval = 600
    static let suggestionLimit = 5

    static func isFresh(lastAttempt: Date?, now: Date, anonymous: Bool) -> Bool {
        guard let lastAttempt else { return false }
        return now.timeIntervalSince(lastAttempt) < (anonymous ? freshAnonymously : freshForGH)
    }

    static func state(
        after result: Result<WatchedPullRequestList, WatchedFailure>, previous: WatchedLoadState?
    ) -> WatchedLoadState {
        switch result {
        case .success(let list): return .loaded(list)
        case .failure(let failure): return .failed(failure, keeping: previous?.list)
        }
    }

    static func count(_ state: WatchedLoadState?) -> String? {
        switch state {
        case .none, .loading:
            return nil
        case .failed:
            return "!"
        case .loaded(let list):
            guard let rows = count(rows: list.pullRequests.count) else { return nil }
            return list.hasMore ? "\(rows)+" : rows
        }
    }

    static func labels(
        for pullRequest: WatchedPullRequest, repository: String, viewerLogin: String?,
        reviewRequests: [ReviewRequest]
    ) -> [String] {
        var labels: [String] = []
        if pullRequest.isDraft { labels.append("draft") }
        if let viewerLogin, pullRequest.author.caseInsensitiveCompare(viewerLogin) == .orderedSame {
            labels.append("yours")
        }
        let requested = reviewRequests.contains {
            $0.number == pullRequest.number && $0.repo.caseInsensitiveCompare(repository) == .orderedSame
        }
        if requested { labels.append("review requested") }
        return labels
    }

    static func suggestions(
        recents: [AnalysisCache.RecentPR], watched: [WatchedRepository], limit: Int = suggestionLimit
    ) -> [String] {
        var seen: Set<String> = []
        var suggestions: [String] = []
        for recent in recents {
            guard let repository = WatchedRepository.parse(recent.repo),
                !watched.contains(where: { $0.matches(repository.id) }),
                seen.insert(repository.id.lowercased()).inserted
            else { continue }
            suggestions.append(repository.id)
        }
        return Array(suggestions.prefix(limit))
    }

    static func canWatch(_ input: String) -> Bool {
        WatchedRepository.parse(input) != nil
    }

    static func emptyMessage(for list: WatchedPullRequestList) -> String {
        list.hasMore
            ? "The newest \(WatchedPullRequests.fetchLimit) open pull requests are all automated."
            : "No open pull requests."
    }

    static func fetchedLabel(_ date: Date) -> String {
        "updated \(date.formatted(.relative(presentation: .named)))"
    }
```

Run: `swift test --filter StartScreenLogicTests`
Expected: PASS.

- [ ] **Step 6: Write the failing model tests**

Create `Tests/ContourTests/StartScreenModelWatchingTests.swift`:

```swift
import Foundation
import Testing
import os

@testable import Contour

@MainActor
struct StartScreenModelWatchingTests {
    private actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private typealias Fetch =
        @Sendable (WatchedRepository, GitHubAccessMode) async -> Result<WatchedPullRequestList, WatchedFailure>

    private func preferences(watching ids: [String] = []) -> Preferences {
        let name = "contour.tests.start.watching.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(defaults: defaults, environment: [:])
        preferences.watchedRepositories = ids.compactMap(WatchedRepository.parse)
        return preferences
    }

    nonisolated private func list(_ numbers: [Int], hasMore: Bool = false) -> WatchedPullRequestList {
        WatchedPullRequestList(
            pullRequests: numbers.map {
                WatchedPullRequest(
                    url: "https://github.com/acme/api/pull/\($0)", number: $0, title: "t\($0)", author: "mwright",
                    isDraft: false, createdAt: nil)
            },
            hasMore: hasMore, fetchedAt: Date(timeIntervalSince1970: 1_000_000))
    }

    private func model(
        preferences: Preferences, clock: Clock = Clock(), anonymous: Bool = false,
        recents: [AnalysisCache.RecentPR] = [], requests: [ReviewRequest]? = nil, login: String? = nil,
        fetch: @escaping Fetch
    ) -> StartScreenModel {
        StartScreenModel(
            preferences: preferences,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { recents }, loadReviewRequests: { requests },
                fetchWatched: fetch, loadViewerLogin: { _ in login },
                usesAnonymousAccess: { _ in anonymous }, now: { clock.now }))
    }

    private func counting(_ calls: OSAllocatedUnfairLock<[String]>, returning list: WatchedPullRequestList) -> Fetch {
        { repository, _ in
            calls.withLock { $0.append(repository.id) }
            return .success(list)
        }
    }

    @Test func watchedRepositoriesAreSourcesInTheOrderTheyWereAdded() {
        let model = model(preferences: preferences(watching: ["acme/web", "acme/api"])) { _, _ in
            .failure(.unavailable)
        }
        #expect(model.sources == [.recents, .watched("acme/web"), .watched("acme/api")])
        #expect(!model.showsWelcome)
    }

    @Test func watchingAddsSelectsStoresAndFetches() async {
        let prefs = preferences()
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(preferences: prefs, fetch: counting(calls, returning: list([1, 2])))
        #expect(await model.watch("https://github.com/acme/api/pull/9"))
        #expect(model.watched.map(\.id) == ["acme/api"])
        #expect(prefs.watchedRepositories.map(\.id) == ["acme/api"])
        #expect(model.selection == .watched("acme/api"))
        #expect(prefs.lastStartSource == .watched("acme/api"))
        #expect(model.state(for: "acme/api") == .loaded(list([1, 2])))
        #expect(model.count(for: .watched("acme/api")) == "2")
        #expect(calls.withLock { $0 } == ["acme/api"])
    }

    @Test func inputThatNamesNoRepositoryChangesNothing() async {
        let prefs = preferences()
        let model = model(preferences: prefs) { _, _ in
            Issue.record("nothing should be fetched")
            return .failure(.unavailable)
        }
        #expect(await model.watch("--flag/x") == false)
        #expect(model.watched.isEmpty)
        #expect(prefs.watchedRepositories.isEmpty)
    }

    @Test func watchingTheSameRepositoryInAnotherCaseSelectsTheExistingEntry() async {
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(
            preferences: preferences(watching: ["Acme/API", "acme/web"]),
            fetch: counting(calls, returning: list([1])))
        model.select(.recents)
        #expect(await model.watch("acme/api"))
        #expect(model.watched.map(\.id) == ["Acme/API", "acme/web"])
        #expect(model.selection == .watched("Acme/API"))
        #expect(calls.withLock { $0 }.isEmpty)
    }

    @Test func isWatchedIgnoresCaseAndNothingIsWatchedWithoutAName() {
        let model = model(preferences: preferences(watching: ["Acme/API"])) { _, _ in .failure(.unavailable) }
        #expect(model.isWatched("acme/api"))
        #expect(!model.isWatched("acme/web"))
        #expect(!model.isWatched(nil))
    }

    @Test func stopWatchingRemovesTheRepositoryItsListAndItsSelection() async {
        let prefs = preferences(watching: ["acme/api", "acme/web"])
        let model = model(preferences: prefs, requests: []) { _, _ in .success(self.list([1])) }
        model.loadRecents()
        await model.loadRemoteSources()
        model.select(.watched("acme/api"))
        model.stopWatching("ACME/api")
        #expect(model.watched.map(\.id) == ["acme/web"])
        #expect(prefs.watchedRepositories.map(\.id) == ["acme/web"])
        #expect(model.state(for: "acme/api") == nil)
        #expect(model.selection == .reviewRequests)
        #expect(prefs.lastStartSource == nil)
    }

    @Test func stopWatchingAnotherRepositoryLeavesTheSelectionAlone() {
        let model = model(preferences: preferences(watching: ["acme/api", "acme/web"])) { _, _ in
            .failure(.unavailable)
        }
        model.select(.watched("acme/web"))
        model.stopWatching("acme/api")
        #expect(model.selection == .watched("acme/web"))
    }

    @Test func toggleWatchAddsThenRemoves() async {
        let model = model(preferences: preferences()) { _, _ in .success(self.list([1])) }
        await model.toggleWatch("acme/api")
        #expect(model.isWatched("acme/api"))
        await model.toggleWatch("acme/api")
        #expect(!model.isWatched("acme/api"))
    }

    @Test func reloadFetchesEveryWatchedRepositoryAndTheViewerOnce() async {
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let logins = OSAllocatedUnfairLock<Int>(initialState: 0)
        let prefs = preferences(watching: ["acme/api", "acme/web"])
        let model = StartScreenModel(
            preferences: prefs,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { [] }, loadReviewRequests: { [] },
                fetchWatched: counting(calls, returning: list([1])),
                loadViewerLogin: { _ in
                    logins.withLock { $0 += 1 }
                    return "jstephens"
                },
                usesAnonymousAccess: { _ in false }, now: { Date(timeIntervalSince1970: 1_000_000) }))
        model.loadRecents()
        await model.loadRemoteSources()
        model.loadRecents()
        await model.loadRemoteSources()
        #expect(Set(calls.withLock { $0 }) == ["acme/api", "acme/web"])
        #expect(calls.withLock { $0 }.count == 2)
        #expect(model.viewerLogin == "jstephens")
        #expect(logins.withLock { $0 } == 1)
    }

    @Test func aCancelledWatchedFetchKeepsNothingAndIsRetriedNextTime() async {
        let gate = Gate()
        let calls = OSAllocatedUnfairLock<Int>(initialState: 0)
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            calls.withLock { $0 += 1 }
            await gate.wait()
            return .failure(.unavailable)
        }
        let first = Task { await model.refresh("acme/api") }
        while model.state(for: "acme/api") == nil { await Task.yield() }
        first.cancel()
        await gate.open()
        await first.value
        #expect(model.state(for: "acme/api") == nil)
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 } == 2)
        #expect(model.state(for: "acme/api") == .failed(.unavailable, keeping: nil))
    }

    @Test func aCancelledRemoteLoadLeavesTheReviewRequestsAlone() async {
        let gate = Gate()
        let prefs = preferences()
        let model = StartScreenModel(
            preferences: prefs,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { [] },
                loadReviewRequests: {
                    await gate.wait()
                    return nil
                }))
        await model.loadReviewRequests()
        let loading = Task { await model.loadRemoteSources() }
        loading.cancel()
        await gate.open()
        await loading.value
        #expect(model.reviewRequests == nil)
    }

    @Test func aFreshListIsNotFetchedAgainUntilItGoesStale() async {
        let clock = Clock()
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(
            preferences: preferences(watching: ["acme/api"]), clock: clock,
            fetch: counting(calls, returning: list([1])))
        await model.refreshWatched(force: false)
        clock.now += 119
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 1)
        clock.now += 1
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 2)
    }

    @Test func anonymousListsStayFreshForTenMinutes() async {
        let clock = Clock()
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(
            preferences: preferences(watching: ["acme/api"]), clock: clock, anonymous: true,
            fetch: counting(calls, returning: list([1])))
        await model.refreshWatched(force: false)
        clock.now += 599
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 1)
        clock.now += 1
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 2)
    }

    @Test func aFailedAttemptAlsoCountsAsFreshSoItIsNotRetriedOnEveryActivation() async {
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(preferences: preferences(watching: ["acme/api"])) { repository, _ in
            calls.withLock { $0.append(repository.id) }
            return .failure(.notFound)
        }
        await model.refreshWatched(force: false)
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 1)
        #expect(model.count(for: .watched("acme/api")) == "!")
    }

    @Test func forcingAndRefreshingOneRepositoryAlwaysFetch() async {
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(
            preferences: preferences(watching: ["acme/api", "acme/web"]),
            fetch: counting(calls, returning: list([1])))
        await model.refreshWatched(force: false)
        await model.refreshWatched(force: true)
        await model.refresh("acme/web")
        await model.refresh("acme/unknown")
        #expect(calls.withLock { $0 }.count == 5)
        #expect(calls.withLock { $0 }.last == "acme/web")
    }

    @Test func oneRepositoryFailingLeavesTheOthersListed() async {
        let model = model(preferences: preferences(watching: ["acme/api", "acme/vault"])) { repository, _ in
            repository.name == "vault" ? .failure(.notFound) : .success(self.list([1, 2]))
        }
        await model.refreshWatched(force: false)
        #expect(model.state(for: "acme/api") == .loaded(list([1, 2])))
        #expect(model.state(for: "acme/vault") == .failed(.notFound, keeping: nil))
    }

    @Test func aFailedRefreshKeepsTheRowsAlreadyShown() async {
        let fails = OSAllocatedUnfairLock<Bool>(initialState: false)
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            fails.withLock { $0 } ? .failure(.unavailable) : .success(self.list([1, 2]))
        }
        await model.refresh("acme/api")
        fails.withLock { $0 = true }
        await model.refresh("acme/api")
        #expect(model.state(for: "acme/api") == .failed(.unavailable, keeping: list([1, 2])))
    }

    @Test func aRepositoryShowsLoadingOnlyUntilItsFirstAnswer() async {
        let gate = Gate()
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            await gate.wait()
            return .success(self.list([1]))
        }
        let refreshing = Task { await model.refresh("acme/api") }
        while model.state(for: "acme/api") == nil { await Task.yield() }
        #expect(model.state(for: "acme/api") == .loading)
        await gate.open()
        await refreshing.value
        #expect(model.state(for: "acme/api") == .loaded(list([1])))
    }

    @Test func aRepositoryRemovedWhileItsFetchIsInFlightLeavesNoStateBehind() async {
        let gate = Gate()
        let prefs = preferences()
        let model = model(preferences: prefs) { _, _ in
            await gate.wait()
            return .success(self.list([1]))
        }
        let adding = Task { await model.watch("acme/api") }
        while model.state(for: "acme/api") == nil { await Task.yield() }
        model.stopWatching("acme/api")
        await gate.open()
        _ = await adding.value
        #expect(model.watched.isEmpty)
        #expect(model.state(for: "acme/api") == nil)
        #expect(model.sources == [.recents])
        #expect(prefs.watchedRepositories.isEmpty)
    }

    @Test func aListOfOnlyBotsHasNoCountAndIsNotTheWelcome() async {
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            .success(self.list([], hasMore: true))
        }
        await model.refreshWatched(force: false)
        #expect(model.count(for: .watched("acme/api")) == nil)
        #expect(!model.showsWelcome)
    }

    @Test func labelsUseTheViewerAndTheLoadedReviewRequests() async {
        let requested = ReviewRequest(
            url: "u", repo: "acme/api", number: 2, title: "t", author: "a", isDraft: false, updatedAt: nil)
        let model = model(
            preferences: preferences(watching: ["acme/api"]), requests: [requested], login: "mwright"
        ) { _, _ in .success(self.list([1, 2])) }
        model.loadRecents()
        await model.loadRemoteSources()
        let rows = model.state(for: "acme/api")?.list?.pullRequests ?? []
        #expect(rows.map { model.labels(for: $0, in: "acme/api") } == [["yours"], ["yours", "review requested"]])
    }

    @Test func failureMessagesSayWhetherAccessIsAnonymous() {
        let anonymous = model(preferences: preferences(), anonymous: true) { _, _ in .failure(.notFound) }
        let signedIn = model(preferences: preferences(), anonymous: false) { _, _ in .failure(.notFound) }
        #expect(
            anonymous.failureMessage(for: .notFound, repository: "acme/api")
                == WatchedPullRequests.message(for: .notFound, repository: "acme/api", anonymous: true))
        #expect(
            signedIn.failureMessage(for: .notFound, repository: "acme/api")
                == WatchedPullRequests.message(for: .notFound, repository: "acme/api", anonymous: false))
    }

    @Test func suggestionsComeFromLoadedRecentsAndLeaveOutWatchedRepositories() async {
        let recents = [
            AnalysisCache.RecentPR(url: "u", repo: "acme/api", number: 1, title: "t", lastOpened: Date()),
            AnalysisCache.RecentPR(url: "u", repo: "acme/web", number: 2, title: "t", lastOpened: Date()),
        ]
        let model = model(preferences: preferences(watching: ["acme/api"]), recents: recents) { _, _ in
            .success(self.list([1]))
        }
        model.loadRecents()
        await model.loadRemoteSources()
        #expect(model.suggestions == ["acme/web"])
    }

    @Test func liveDependenciesChooseAnonymousAccessWhenToldTo() {
        let live = StartScreenModel.Dependencies.live
        #expect(live.usesAnonymousAccess(.anonymous))
        #expect(live.now() <= Date())
    }
}
```

- [ ] **Step 7: Run to verify they fail**

Run: `swift test --filter StartScreenModelWatchingTests`
Expected: FAIL to compile with "extra arguments at positions ... in call" on `Dependencies(`.

- [ ] **Step 8: Implement the model**

Replace the contents of `Sources/Contour/Views/Start/StartScreenModel.swift`:

```swift
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class StartScreenModel {
    typealias WatchedFetch =
        @Sendable (WatchedRepository, GitHubAccessMode) async -> Result<WatchedPullRequestList, WatchedFailure>

    struct Dependencies {
        var loadRecents: () -> [AnalysisCache.RecentPR]
        var loadReviewRequests: @MainActor () async -> [ReviewRequest]?
        var fetchWatched: WatchedFetch = { _, _ in .failure(.unavailable) }
        var loadViewerLogin: @Sendable (GitHubAccessMode) async -> String? = { _ in nil }
        var usesAnonymousAccess: (GitHubAccessMode) -> Bool = { $0 == .anonymous }
        var now: () -> Date = { Date() }

        @MainActor static var live: Dependencies {
            let service = WatchedPullRequests()
            return Dependencies(
                loadRecents: { AnalysisCache().recentPRs(limit: StartScreenLogic.rowsShown) },
                loadReviewRequests: {
                    await ReviewRequests.fetch(access: Preferences.shared.resolvedGitHubAccess)
                },
                fetchWatched: { await service.fetch($0, access: $1) },
                loadViewerLogin: { await service.viewerLogin(access: $0) },
                usesAnonymousAccess: {
                    WatchedPullRequests.transport(access: $0, ghAvailable: Shell.which("gh") != nil) == .rest
                },
                now: { Date() })
        }
    }

    private(set) var recents: [AnalysisCache.RecentPR] = []
    private(set) var reviewRequests: [ReviewRequest]?
    private(set) var watched: [WatchedRepository]
    private(set) var viewerLogin: String?
    private var states: [String: WatchedLoadState] = [:]
    private var remembered: StartSource?

    @ObservationIgnored private var lastAttempts: [String: Date] = [:]
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let dependencies: Dependencies

    init(preferences: Preferences, dependencies: Dependencies) {
        self.preferences = preferences
        self.dependencies = dependencies
        watched = preferences.watchedRepositories
        remembered = preferences.lastStartSource
    }

    var visibleReviewRequests: [ReviewRequest] {
        StartScreenLogic.visibleRequests(reviewRequests, limit: StartScreenLogic.rowsShown)
    }

    var sources: [StartSource] {
        StartScreenLogic.sources(reviewRequestsAvailable: reviewRequests != nil, watched: watched.map(\.id))
    }

    var selection: StartSource {
        StartScreenLogic.resolvedSelection(remembered: remembered, sources: sources)
    }

    var selectionBinding: Binding<StartSource?> {
        Binding(
            get: { self.selection },
            set: { if let source = $0 { self.select(source) } }
        )
    }

    var showsWelcome: Bool {
        StartScreenLogic.showsWelcome(
            requests: visibleReviewRequests, recents: recents, watchedCount: watched.count)
    }

    var suggestions: [String] {
        StartScreenLogic.suggestions(recents: recents, watched: watched)
    }

    func select(_ source: StartSource) {
        remembered = source
        preferences.lastStartSource = source
    }

    func count(for source: StartSource) -> String? {
        switch source {
        case .reviewRequests: return StartScreenLogic.count(rows: visibleReviewRequests.count)
        case .recents: return nil
        case .watched(let id): return StartScreenLogic.count(states[id])
        }
    }

    func state(for id: String) -> WatchedLoadState? { states[id] }

    func isWatched(_ id: String?) -> Bool {
        guard let id else { return false }
        return watched.contains { $0.matches(id) }
    }

    func labels(for pullRequest: WatchedPullRequest, in repository: String) -> [String] {
        StartScreenLogic.labels(
            for: pullRequest, repository: repository, viewerLogin: viewerLogin,
            reviewRequests: reviewRequests ?? [])
    }

    func failureMessage(for failure: WatchedFailure, repository: String) -> String {
        WatchedPullRequests.message(
            for: failure, repository: repository,
            anonymous: dependencies.usesAnonymousAccess(preferences.resolvedGitHubAccess))
    }

    func loadRecents() {
        recents = dependencies.loadRecents()
    }

    func loadReviewRequests() async {
        let result = await dependencies.loadReviewRequests()
        guard !Task.isCancelled else { return }
        reviewRequests = result
    }

    func loadRemoteSources() async {
        async let refreshing: Void = refreshWatched(force: false)
        await loadReviewRequests()
        if viewerLogin == nil {
            let login = await dependencies.loadViewerLogin(preferences.resolvedGitHubAccess)
            if !Task.isCancelled { viewerLogin = login }
        }
        await refreshing
    }

    @discardableResult
    func watch(_ input: String) async -> Bool {
        guard let repository = WatchedRepository.parse(input) else { return false }
        if let existing = watched.first(where: { $0.matches(repository.id) }) {
            select(.watched(existing.id))
            return true
        }
        watched.append(repository)
        preferences.watchedRepositories = watched
        select(.watched(repository.id))
        await refresh(repository.id)
        return true
    }

    func stopWatching(_ id: String) {
        guard let repository = watched.first(where: { $0.matches(id) }) else { return }
        watched.removeAll { $0.id == repository.id }
        preferences.watchedRepositories = watched
        states[repository.id] = nil
        lastAttempts[repository.id] = nil
        if remembered == .watched(repository.id) {
            remembered = nil
            preferences.lastStartSource = nil
        }
    }

    func toggleWatch(_ id: String) async {
        if isWatched(id) {
            stopWatching(id)
        } else {
            await watch(id)
        }
    }

    func refresh(_ id: String) async {
        guard let repository = watched.first(where: { $0.matches(id) }) else { return }
        await fetch([repository])
    }

    func refreshWatched(force: Bool) async {
        let anonymous = dependencies.usesAnonymousAccess(preferences.resolvedGitHubAccess)
        let moment = dependencies.now()
        await fetch(
            watched.filter {
                force || !StartScreenLogic.isFresh(lastAttempt: lastAttempts[$0.id], now: moment, anonymous: anonymous)
            })
    }

    private func fetch(_ repositories: [WatchedRepository]) async {
        let access = preferences.resolvedGitHubAccess
        let fetchWatched = dependencies.fetchWatched
        let moment = dependencies.now()
        for repository in repositories {
            lastAttempts[repository.id] = moment
            if states[repository.id] == nil { states[repository.id] = .loading }
        }
        await withTaskGroup(of: (String, Result<WatchedPullRequestList, WatchedFailure>).self) { group in
            for repository in repositories {
                group.addTask { (repository.id, await fetchWatched(repository, access)) }
            }
            for await (id, result) in group where watched.contains(where: { $0.id == id }) {
                if Task.isCancelled {
                    lastAttempts[id] = nil
                    if states[id] == .loading { states[id] = nil }
                    continue
                }
                states[id] = StartScreenLogic.state(after: result, previous: states[id])
            }
        }
    }
}
```

- [ ] **Step 9: Run to verify they pass**

Run: `swift test --filter StartScreenModel`
Expected: PASS for both `StartScreenModelTests` and `StartScreenModelWatchingTests`.

- [ ] **Step 10: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add Sources/Contour Tests/ContourTests
git commit -m "Keep the watch list and each repository's pull requests in the model

The watch list lives in Preferences so clearing the analysis cache keeps
it. Lists live in memory and are refetched when stale: two minutes under
gh, ten anonymously, because anonymous access shares 60 requests an hour
with opening pull requests. A failed attempt counts towards freshness so
a missing repository isn't retried on every activation. Results for a
repository removed mid-fetch are discarded."
```

### Task 10: The Watched group, its list and the add popover

**Files:**
- Modify: `Sources/Contour/Views/Start/StartScreenLogic.swift` (`subtitle` takes an optional repository)
- Modify: `Sources/Contour/Views/Start/PullRequestRows.swift`
- Create: `Sources/Contour/Views/Start/StartScreenActions.swift`
- Create: `Sources/Contour/Views/Start/WatchedPullRequestsList.swift`
- Create: `Sources/Contour/Views/Start/WatchRepositoryPopover.swift`
- Modify: `Sources/Contour/Views/Start/StartSidebar.swift`
- Modify: `Sources/Contour/Views/Start/StartSourceList.swift`
- Modify: `Sources/Contour/Views/Start/StartScreenView.swift`
- Modify: `Tests/ContourTests/StartScreenLogicTests.swift`
- Modify: `Tests/ContourTests/StartScreenViewRenderTests.swift`
- Modify: `Tests/ContourTests/StartScreenViewHostingTests.swift`
- Create: `Tests/ContourTests/StartScreenActionsTests.swift`

**Interfaces:**
- Consumes: everything Task 9 produces.
- Produces:
  - `StartScreenLogic.subtitle(repo: String?, number:detail:date:dateVerb:)`
  - `PullRequestRow` gains `repo: String?` and `labels: [String] = []`
  - `struct StartMenuItem: Identifiable` with `title: String`, `isDestructive: Bool`, `action: () -> Void`
  - `@MainActor struct StartScreenActions` with `init(model:openURL:spawn:)`, `func refresh(_ id: String) -> () -> Void`, `func watch(_ input: String)`, `func refreshStale()`, `func toggleWatch(_ id: String) -> () -> Void`, `func menu(for repository: WatchedRepository) -> [StartMenuItem]`
  - `WatchedPullRequestsList(repository:state:labels:failureMessage:onRefresh:onOpen:)`
  - `WatchRepositoryPopover(suggestions:initialText:onWatch:)`
  - `StartSidebar(model:actions:markNamespace:)`, `StartSourceList(model:actions:onOpen:)`

- [ ] **Step 1: Write the failing tests for the subtitle and the actions**

Append to `StartScreenLogicTests`:

```swift
    @Test func aRowInARepositorysOwnListLeavesTheRepositoryOut() {
        #expect(
            StartScreenLogic.subtitle(repo: nil, number: 42, detail: "mwright", date: nil, dateVerb: "opened")
                == "#42 · mwright")
    }
```

Create `Tests/ContourTests/StartScreenActionsTests.swift`:

```swift
import Foundation
import Testing

@testable import Contour

@MainActor
struct StartScreenActionsTests {
    private final class Spawned {
        var operations: [@MainActor () async -> Void] = []

        func runAll() async {
            let pending = operations
            operations = []
            for operation in pending { await operation() }
        }
    }

    private final class Opened {
        var urls: [URL] = []
    }

    private func preferences(watching ids: [String] = []) -> Preferences {
        let name = "contour.tests.start.actions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(defaults: defaults, environment: [:])
        preferences.watchedRepositories = ids.compactMap(WatchedRepository.parse)
        return preferences
    }

    private let list = WatchedPullRequestList(
        pullRequests: [
            WatchedPullRequest(
                url: "https://github.com/acme/api/pull/1", number: 1, title: "t", author: "a", isDraft: false,
                createdAt: nil)
        ], hasMore: false, fetchedAt: Date(timeIntervalSince1970: 1_000_000))

    private func model(watching ids: [String] = []) -> StartScreenModel {
        let list = list
        return StartScreenModel(
            preferences: preferences(watching: ids),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { [] }, loadReviewRequests: { nil }, fetchWatched: { _, _ in .success(list) }))
    }

    private func actions(_ model: StartScreenModel, _ spawned: Spawned, _ opened: Opened = Opened())
        -> StartScreenActions
    {
        StartScreenActions(
            model: model, openURL: { opened.urls.append($0) }, spawn: { spawned.operations.append($0) })
    }

    @Test func watchAddsTheRepositoryOnceTheSpawnedWorkRuns() async {
        let model = model()
        let spawned = Spawned()
        actions(model, spawned).watch("acme/api")
        #expect(model.watched.isEmpty)
        await spawned.runAll()
        #expect(model.watched.map(\.id) == ["acme/api"])
        #expect(model.state(for: "acme/api") == .loaded(list))
    }

    @Test func refreshFetchesThatRepository() async {
        let model = model(watching: ["acme/api"])
        let spawned = Spawned()
        actions(model, spawned).refresh("acme/api")()
        await spawned.runAll()
        #expect(model.state(for: "acme/api") == .loaded(list))
    }

    @Test func refreshStaleFetchesWhatHasNeverBeenFetched() async {
        let model = model(watching: ["acme/api", "acme/web"])
        let spawned = Spawned()
        actions(model, spawned).refreshStale()
        await spawned.runAll()
        #expect(model.state(for: "acme/api") == .loaded(list))
        #expect(model.state(for: "acme/web") == .loaded(list))
    }

    @Test func toggleWatchAddsAndThenRemoves() async {
        let model = model()
        let spawned = Spawned()
        let actions = actions(model, spawned)
        actions.toggleWatch("acme/api")()
        await spawned.runAll()
        #expect(model.isWatched("acme/api"))
        actions.toggleWatch("acme/api")()
        await spawned.runAll()
        #expect(!model.isWatched("acme/api"))
    }

    @Test func aWatchedRepositorysMenuRefreshesOpensAndStopsWatching() async {
        let model = model(watching: ["acme/api"])
        let spawned = Spawned()
        let opened = Opened()
        let repository = WatchedRepository(owner: "acme", name: "api")
        let menu = actions(model, spawned, opened).menu(for: repository)

        #expect(menu.map(\.title) == ["Refresh", "Open Repository on GitHub", "Stop Watching acme/api"])
        #expect(menu.map(\.isDestructive) == [false, false, true])
        #expect(menu.map(\.id) == menu.map(\.title))

        menu[0].action()
        await spawned.runAll()
        #expect(model.state(for: "acme/api") == .loaded(list))

        menu[1].action()
        #expect(opened.urls == [URL(string: "https://github.com/acme/api")!])

        menu[2].action()
        #expect(model.watched.isEmpty)
    }

    @Test func theDefaultSpawnRunsTheWork() async {
        let model = model()
        StartScreenActions(model: model).watch("acme/api")
        while !model.isWatched("acme/api") { await Task.yield() }
        while model.state(for: "acme/api")?.list == nil { await Task.yield() }
        #expect(model.watched.map(\.id) == ["acme/api"])
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter StartScreenActionsTests`
Expected: FAIL to compile with "cannot find 'StartScreenActions' in scope".

- [ ] **Step 3: Implement the subtitle change and the actions**

In `StartScreenLogic.swift`, change `subtitle`:

```swift
    static func subtitle(repo: String?, number: Int, detail: String?, date: Date?, dateVerb: String) -> String {
        var parts = [repo.map { "\($0) #\(number)" } ?? "#\(number)"]
        if let detail { parts.append(detail) }
        if let date { parts.append("\(dateVerb) \(date.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: " · ")
    }
```

Create `Sources/Contour/Views/Start/StartScreenActions.swift`:

```swift
import AppKit
import Foundation

struct StartMenuItem: Identifiable {
    var title: String
    var isDestructive = false
    var action: () -> Void

    var id: String { title }
}

@MainActor
struct StartScreenActions {
    typealias Spawn = (@escaping @MainActor () async -> Void) -> Void

    let model: StartScreenModel
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var spawn: Spawn = { operation in Task { await operation() } }

    func watch(_ input: String) {
        spawn { await model.watch(input) }
    }

    func refresh(_ id: String) -> () -> Void {
        { spawn { await model.refresh(id) } }
    }

    func refreshStale() {
        spawn { await model.refreshWatched(force: false) }
    }

    func toggleWatch(_ id: String) -> () -> Void {
        { spawn { await model.toggleWatch(id) } }
    }

    func menu(for repository: WatchedRepository) -> [StartMenuItem] {
        [
            StartMenuItem(title: "Refresh", action: refresh(repository.id)),
            StartMenuItem(
                title: "Open Repository on GitHub",
                action: { if let url = repository.url { openURL(url) } }),
            StartMenuItem(
                title: "Stop Watching \(repository.id)", isDestructive: true,
                action: { model.stopWatching(repository.id) }),
        ]
    }
}
```

Run: `swift test --filter StartScreenActionsTests && swift test --filter StartScreenLogicTests`
Expected: PASS.

- [ ] **Step 4: Give rows their labels**

In `PullRequestRows.swift`, replace `struct PullRequestRow`:

```swift
struct PullRequestRow: View {
    let title: String
    let repo: String?
    let number: Int
    let detail: String?
    let date: Date?
    let dateVerb: String
    let url: String
    var labels: [String] = []
    var onOpen: (String) -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            onOpen(url)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ForEach(labels, id: \.self) { label in
                        PullRequestLabel(text: label)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url)
    }

    private var subtitle: String {
        StartScreenLogic.subtitle(repo: repo, number: number, detail: detail, date: date, dateVerb: dateVerb)
    }
}

struct PullRequestLabel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18)))
    }
}
```

`Text(verbatim:)` for the title is deliberate: a pull request title is untrusted and must not be read as Markdown or a localization key.

- [ ] **Step 5: Write the watched list**

Create `Sources/Contour/Views/Start/WatchedPullRequestsList.swift`:

```swift
import SwiftUI

struct WatchedPullRequestsList: View {
    let repository: String
    let state: WatchedLoadState?
    var labels: (WatchedPullRequest) -> [String]
    var failureMessage: (WatchedFailure) -> String
    var onRefresh: () -> Void
    var onOpen: (String) -> Void

    var body: some View {
        StartListHeader(
            title: "\(repository) · open pull requests",
            systemImage: StartScreenLogic.symbol(for: .watched(repository))
        ) {
            if let list = state?.list {
                Text(verbatim: StartScreenLogic.fetchedLabel(list.fetchedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")
        }
        if let failure = state?.failure {
            WatchedFailureMessage(text: failureMessage(failure), onRetry: onRefresh)
        }
        if state == nil || state == .loading {
            ProgressView()
                .controlSize(.small)
                .padding(8)
        }
        if let list = state?.list {
            if list.pullRequests.isEmpty {
                StartEmptyMessage(text: StartScreenLogic.emptyMessage(for: list))
            }
            ForEach(list.pullRequests) { pullRequest in
                PullRequestRow(
                    title: pullRequest.title, repo: nil, number: pullRequest.number,
                    detail: pullRequest.author, date: pullRequest.createdAt, dateVerb: "opened",
                    url: pullRequest.url, labels: labels(pullRequest), onOpen: onOpen
                )
            }
        }
    }
}

struct WatchedFailureMessage: View {
    let text: String
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: onRetry)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 6: Write the popover**

Create `Sources/Contour/Views/Start/WatchRepositoryPopover.swift`:

```swift
import SwiftUI

struct WatchRepositoryPopover: View {
    let suggestions: [String]
    var onWatch: (String) -> Void
    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(suggestions: [String], initialText: String = "", onWatch: @escaping (String) -> Void) {
        self.suggestions = suggestions
        self.onWatch = onWatch
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("owner/repo or a GitHub URL", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(confirm)
                Button("Watch", action: confirm)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!StartScreenLogic.canWatch(text))
            }
            if !suggestions.isEmpty {
                Text("From your recent pull requests")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onWatch(suggestion)
                    } label: {
                        Text(verbatim: suggestion)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { fieldFocused = true }
    }

    private func confirm() {
        guard StartScreenLogic.canWatch(text) else { return }
        onWatch(text)
    }
}
```

- [ ] **Step 7: Add the Watched group to the sidebar**

Replace `struct StartSidebar` in `StartSidebar.swift` (`StartSourceRow` is unchanged):

```swift
struct StartSidebar: View {
    let model: StartScreenModel
    let actions: StartScreenActions
    var markNamespace: Namespace.ID
    @State private var choosingRepository = false

    static let markHeight: CGFloat = 24

    var body: some View {
        List(selection: model.selectionBinding) {
            ForEach(model.sources.filter { !Self.isWatched($0) }, id: \.self) { source in
                StartSourceRow(source: source, count: model.count(for: source))
            }
            Section("Watched") {
                ForEach(model.watched) { repository in
                    StartSourceRow(
                        source: .watched(repository.id), count: model.count(for: .watched(repository.id))
                    )
                    .tag(StartSource.watched(repository.id))
                    .contextMenu { StartMenu(items: actions.menu(for: repository)) }
                }
                Button {
                    choosingRepository = true
                } label: {
                    Label("Watch a repository…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .selectionDisabled()
                .popover(isPresented: $choosingRepository, arrowEdge: .trailing) {
                    WatchRepositoryPopover(suggestions: model.suggestions) { input in
                        choosingRepository = false
                        actions.watch(input)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
    }

    nonisolated static func isWatched(_ source: StartSource) -> Bool {
        if case .watched = source { return true }
        return false
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !model.showsWelcome {
                ContourMarkView()
                    .matchesContourMark(in: markNamespace)
                    .frame(height: Self.markHeight)
            }
            Text("Contour")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct StartMenu: View {
    let items: [StartMenuItem]

    var body: some View {
        ForEach(items) { item in
            Button(item.title, role: item.isDestructive ? .destructive : nil, action: item.action)
        }
    }
}
```

- [ ] **Step 8: Show the watched list for a watched selection**

In `StartSourceList.swift`, add the stored property `let actions: StartScreenActions` after `model`, and replace the `.watched` case of the switch:

```swift
                case .watched(let id):
                    WatchedPullRequestsList(
                        repository: id, state: model.state(for: id),
                        labels: { model.labels(for: $0, in: id) },
                        failureMessage: { model.failureMessage(for: $0, repository: id) },
                        onRefresh: actions.refresh(id), onOpen: onOpen
                    )
```

In `StartScreenView.swift`, add a stored property `private let actions: StartScreenActions` and an initializer parameter `actions: StartScreenActions? = nil` placed after `pasteboard`, resolved in `init` as:

```swift
        self.actions = actions ?? StartScreenActions(model: model)
```

Pass it on: `StartSidebar(model: model, actions: actions, markNamespace: markNamespace)` and `StartSourceList(model: model, actions: actions, onOpen: onSubmit)`. In the view's `.task`, replace `await model.loadReviewRequests()` with `await model.loadRemoteSources()`, so the body reads `model.loadRecents(); await checkClipboard(); await model.loadRemoteSources()`. Refresh stale lists when the app becomes active:

```swift
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkClipboard() }
            actions.refreshStale()
        }
```

- [ ] **Step 9: Write the view tests**

In `StartScreenViewRenderTests.swift`, change the `loaded` helper to take watched repositories and states, and pass `actions` wherever `StartSidebar` and `StartSourceList` are built:

```swift
    private func loaded(
        recents: [AnalysisCache.RecentPR], requests: [ReviewRequest]?, selecting source: StartSource? = nil,
        watching: [String] = [],
        fetch: @escaping StartScreenModel.WatchedFetch = { _, _ in .failure(.unavailable) }
    ) async -> StartScreenModel {
        let prefs = preferences()
        prefs.watchedRepositories = watching.compactMap(WatchedRepository.parse)
        let model = StartScreenModel(
            preferences: prefs,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { recents }, loadReviewRequests: { requests }, fetchWatched: fetch))
        model.loadRecents()
        await model.loadRemoteSources()
        if let source { model.select(source) }
        return model
    }

    private func watchedList(_ count: Int, hasMore: Bool = false) -> WatchedPullRequestList {
        WatchedPullRequestList(
            pullRequests: count == 0
                ? []
                : (1...count).map {
                    WatchedPullRequest(
                        url: "https://github.com/acme/api/pull/\($0)", number: $0, title: "t\($0)",
                        author: "mwright", isDraft: $0 == 1, createdAt: Date())
                },
            hasMore: hasMore, fetchedAt: Date())
    }
```

Add:

```swift
    @Test func theBrowserLaysOutWithAWatchedRepositorySelected() async {
        let list = watchedList(10, hasMore: true)
        let model = await loaded(
            recents: recents(), requests: requests(), selecting: .watched("acme/api"),
            watching: ["acme/api", "acme/web"], fetch: { _, _ in .success(list) })
        #expect(model.count(for: .watched("acme/api")) == "10+")
        _ = render(NamespaceHost { StartScreenView(model: model, markNamespace: $0, onSubmit: { _ in }) })
        _ = render(
            StartSourceList(model: model, actions: StartScreenActions(model: model), onOpen: { _ in }))
    }

    @Test func theWatchedListLaysOutInEveryState() {
        let states: [WatchedLoadState?] = [
            nil, .loading, .loaded(watchedList(3)), .loaded(watchedList(0)),
            .loaded(watchedList(0, hasMore: true)), .failed(.notFound, keeping: nil),
            .failed(.rateLimited(resetAt: Date()), keeping: watchedList(2)),
        ]
        for state in states {
            let size = render(
                VStack(alignment: .leading) {
                    WatchedPullRequestsList(
                        repository: "acme/api", state: state, labels: { _ in ["draft", "yours"] },
                        failureMessage: { _ in "Couldn't list pull requests for acme/api." },
                        onRefresh: {}, onOpen: { _ in })
                })
            #expect(size.height > 0)
        }
    }

    @Test func aRowWithAHostileTitleStaysOneLineTall() {
        func height(_ title: String) -> CGFloat {
            render(
                PullRequestRow(
                    title: title, repo: nil, number: 1, detail: "mwright", date: nil, dateVerb: "opened",
                    url: "https://github.com/acme/api/pull/1", labels: ["draft"], onOpen: { _ in }
                ).frame(width: 500)
            ).height
        }
        let plain = height("Fix it")
        #expect(height(String(repeating: "A very long title ", count: 60)) == plain)
        #expect(height("first line\nsecond line\nthird line") == plain)
        #expect(height("**bold** [link](https://example.com) `code`") == plain)
    }

    @Test func labelsFailureMessagesAndMenusLayOut() {
        #expect(render(PullRequestLabel(text: "review requested")).width > 0)
        #expect(render(WatchedFailureMessage(text: "Couldn't list pull requests.", onRetry: {})).height > 0)
        #expect(
            render(
                Menu("m") {
                    StartMenu(items: [
                        StartMenuItem(title: "Refresh", action: {}),
                        StartMenuItem(title: "Stop Watching acme/api", isDestructive: true, action: {}),
                    ])
                }
            ).width > 0)
    }

    @Test func thePopoverLaysOutWithAndWithoutSuggestions() {
        #expect(render(WatchRepositoryPopover(suggestions: [], onWatch: { _ in })).width > 0)
        #expect(
            render(WatchRepositoryPopover(suggestions: ["acme/web", "acme/infra"], onWatch: { _ in })).height > 0)
    }

    @Test func onlyWatchedSourcesAreInTheWatchedGroup() {
        #expect(StartSidebar.isWatched(.watched("acme/api")))
        #expect(!StartSidebar.isWatched(.recents))
        #expect(!StartSidebar.isWatched(.reviewRequests))
    }
```

In `StartScreenViewHostingTests.swift`, add:

```swift
    private func hostPopover(initialText: String, watched: @escaping (String) -> Void) -> NSWindow {
        _ = NSApplication.shared
        let hosting = NSHostingView(
            rootView: WatchRepositoryPopover(suggestions: [], initialText: initialText, onWatch: watched))
        let window = HeadlessWindow(size: NSSize(width: 360, height: 160), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        return window
    }

    @Test func returnInThePopoverWatchesAValidRepository() {
        let recorder = Recorder()
        let window = hostPopover(initialText: "acme/api") { recorder.submitted.append($0) }
        pressReturn(in: window)
        #expect(recorder.submitted == ["acme/api"])
        window.close()
    }

    @Test func returnInThePopoverIgnoresInputThatNamesNoRepository() {
        let recorder = Recorder()
        let window = hostPopover(initialText: "--flag/x") { recorder.submitted.append($0) }
        pressReturn(in: window)
        #expect(recorder.submitted.isEmpty)
        window.close()
    }

    @Test func returningToTheAppRefreshesStaleWatchedLists() {
        let recorder = Recorder()
        let prefs = preferences()
        prefs.watchedRepositories = [WatchedRepository(owner: "acme", name: "api")]
        let model = StartScreenModel(
            preferences: prefs,
            dependencies: StartScreenModel.Dependencies(loadRecents: { [] }, loadReviewRequests: { nil }))
        var refreshes = 0
        let actions = StartScreenActions(model: model, spawn: { _ in refreshes += 1 })
        let view = NamespaceHost { namespace in
            StartScreenView(
                model: model, markNamespace: namespace, pasteboard: self.pasteboard(holding: nil),
                actions: actions, onSubmit: { recorder.submitted.append($0) })
        }
        let hosting = NSHostingView(rootView: view)
        let window = HeadlessWindow(size: NSSize(width: 1080, height: 720), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        settle(hosting)
        #expect(refreshes >= 1)
        window.close()
    }
```

- [ ] **Step 10: Build and run**

Run: `swift build && swift test --filter StartScreen`
Expected: PASS.

- [ ] **Step 11: See it**

Using the in-process snapshot procedure from Task 4 Step 9, launch with `swift run Contour`, watch `cli/cli` through the popover, and capture: the Watched group with a count, the list with `draft` and `yours` labels, the popover with suggestions, and a repository that does not exist (`acme/does-not-exist-12345`) showing its message and **Try again**. Check at 1080×772 and 1728×1080. Delete the debug file afterwards.

- [ ] **Step 12: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add -A Sources/Contour Tests/ContourTests
git commit -m "List watched repositories in the sidebar and their pull requests beside it

Each watched repository is a sidebar source with a count. Its list shows
up to ten open pull requests with labels for drafts, the viewer's own
and those whose review was requested. Repositories are added from a
popover that suggests the ones opened recently, and managed from a
context menu. Titles are rendered verbatim because they are untrusted."
```

### Task 11: Watch from the File menu

**Files:**
- Modify: `Sources/Contour/Views/PRSessionCommands.swift`
- Modify: `Sources/Contour/Views/ContentView.swift`
- Modify: `Tests/ContourTests/PRSessionCommandsTests.swift`

**Interfaces:**
- Consumes: `StartScreenModel.isWatched(_:)`, `StartScreenActions.toggleWatch(_:)` (Tasks 9 and 10), `GitHubService.parse(prURL:)`.
- Produces:
  - `PRSessionActions` gains `repository: String? = nil`, `isWatchingRepository: Bool = false`, `toggleWatch: () -> Void = {}`
  - `PRSessionCommandsLogic.watchTitle(_:) -> String`, `.watchEnabled(_:) -> Bool`, `.repository(fromPullRequestURL:) -> String?`
  - `PRSessionMenuActions.toggleWatch()`

- [ ] **Step 1: Write the failing tests**

Append to `PRSessionCommandsTests`:

```swift
    private func session(repository: String?, watching: Bool, toggle: @escaping () -> Void = {})
        -> PRSessionActions
    {
        PRSessionActions(
            hasOpenPR: repository != nil, pullRequestURL: nil, openDifferent: {}, close: {},
            repository: repository, isWatchingRepository: watching, toggleWatch: toggle)
    }

    @Test func theWatchItemNamesTheRepositoryAndWhatItWillDo() {
        #expect(
            PRSessionCommandsLogic.watchTitle(session(repository: "acme/api", watching: false)) == "Watch acme/api")
        #expect(
            PRSessionCommandsLogic.watchTitle(session(repository: "acme/api", watching: true))
                == "Stop Watching acme/api")
    }

    @Test func withNoPullRequestOpenTheWatchItemIsGenericAndDisabled() {
        #expect(PRSessionCommandsLogic.watchTitle(nil) == "Watch Repository")
        #expect(PRSessionCommandsLogic.watchTitle(session(repository: nil, watching: false)) == "Watch Repository")
        #expect(!PRSessionCommandsLogic.watchEnabled(nil))
        #expect(!PRSessionCommandsLogic.watchEnabled(session(repository: nil, watching: false)))
        #expect(PRSessionCommandsLogic.watchEnabled(session(repository: "acme/api", watching: false)))
    }

    @Test func theRepositoryComesFromThePullRequestURL() {
        #expect(
            PRSessionCommandsLogic.repository(fromPullRequestURL: "https://github.com/acme/api/pull/42")
                == "acme/api")
        #expect(PRSessionCommandsLogic.repository(fromPullRequestURL: nil) == nil)
        #expect(PRSessionCommandsLogic.repository(fromPullRequestURL: "not a link") == nil)
    }

    @MainActor
    @Test func theMenuActionTogglesWatchingThroughTheSession() {
        var toggles = 0
        let actions = PRSessionMenuActions(
            session: session(repository: "acme/api", watching: false, toggle: { toggles += 1 }))
        actions.toggleWatch()
        #expect(toggles == 1)
        PRSessionMenuActions(session: nil).toggleWatch()
        #expect(toggles == 1)
    }

    @Test func aSessionBuiltWithoutWatchDetailsCannotBeWatched() {
        let plain = PRSessionActions(hasOpenPR: true, pullRequestURL: nil, openDifferent: {}, close: {})
        #expect(plain.repository == nil)
        #expect(!plain.isWatchingRepository)
        plain.toggleWatch()
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter PRSessionCommandsTests`
Expected: FAIL to compile with "extra arguments at positions #5, #6, #7 in call".

- [ ] **Step 3: Implement**

In `PRSessionCommands.swift`, add to `struct PRSessionActions` after `close`:

```swift
    var repository: String?
    var isWatchingRepository = false
    var toggleWatch: () -> Void = {}
```

Add to `enum PRSessionCommandsLogic`:

```swift
    static func watchEnabled(_ session: PRSessionActions?) -> Bool { session?.repository != nil }

    static func watchTitle(_ session: PRSessionActions?) -> String {
        guard let session, let repository = session.repository else { return "Watch Repository" }
        return session.isWatchingRepository ? "Stop Watching \(repository)" : "Watch \(repository)"
    }

    static func repository(fromPullRequestURL url: String?) -> String? {
        guard let url, let parsed = try? GitHubService.parse(prURL: url) else { return nil }
        return "\(parsed.owner)/\(parsed.repo)"
    }
```

Add to `struct PRSessionMenuActions`:

```swift
    func toggleWatch() { session?.toggleWatch() }
```

In `groups(session:actions:)`, after the "Copy Link to Pull Request" button:

```swift
            Button(PRSessionCommandsLogic.watchTitle(session), action: actions.toggleWatch)
                .disabled(!PRSessionCommandsLogic.watchEnabled(session))
```

In `ContentView.swift`, replace `sessionActions`:

```swift
    private var sessionActions: PRSessionActions {
        let repository =
            store.hasOpenPR ? PRSessionCommandsLogic.repository(fromPullRequestURL: store.lastPRURL) : nil
        return PRSessionActions(
            hasOpenPR: store.hasOpenPR,
            pullRequestURL: store.pullRequestURL,
            openDifferent: actions.openDifferent(focusRequest: $urlFieldFocusRequest),
            close: actions.close,
            repository: repository,
            isWatchingRepository: startScreen.isWatched(repository),
            toggleWatch: repository.map(StartScreenActions(model: startScreen).toggleWatch) ?? {}
        )
    }
```

If `GitHubService.parse(prURL:)` accepts `"not a link"` without throwing, the third test fails; in that case guard with `GitHubService.normalize(url) != nil` before parsing.

- [ ] **Step 4: Run to verify they pass**

Run: `swift build && swift test --filter PRSessionCommandsTests && swift test --filter ContentView`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
git add Sources/Contour/Views Tests/ContourTests/PRSessionCommandsTests.swift
git commit -m "Watch the open pull request's repository from the File menu

While reviewing is when a reviewer decides a repository is worth
following, so the File menu offers it without a trip back to the start
screen. The item names the repository and reads Stop Watching once it
is watched."
```

### Task 12: Document watching and ship Part 2

**Files:**
- Modify: `DESIGN.md` §4.1a and §16
- Modify: `README.md`

**Interfaces:**
- Consumes: everything from Tasks 6 to 11.
- Produces: a merged pull request.

- [ ] **Step 1: Extend the Start bullet in DESIGN.md §4.1a**

After the sentence ending "and the PRs opened most recently." in the `- **Start.**` bullet, insert:

```markdown
  Below them, a Watched group holds the repositories the user chose to follow, for
  finding review work nobody asked them for. Each lists its ten newest open PRs that
  weren't opened by a bot (`gh pr list -R owner/repo --state open`, or the REST
  `pulls` endpoint anonymously), labelled `draft`, `yours` and `review requested`
  where they apply. Thirty are fetched so that removing bots still leaves ten.
  Lists are held in memory and refetched when older than two minutes under `gh` or
  ten anonymously, since anonymous access shares 60 requests an hour with opening
  PRs. Repositories are added from the sidebar, or from the File menu while a PR is
  open; the list itself is a preference, so clearing the analysis cache keeps it.
```

- [ ] **Step 2: Add the security note to DESIGN.md §16**

Append to the list in §16:

```markdown
- A watched repository's name is parsed and held to GitHub's owner and repository
  character set before it is stored or passed to `gh`, and an owner cannot start with
  a hyphen, so user input can't become a flag. PR titles and author logins on the
  start screen are rendered verbatim and never reach a harness prompt.
```

- [ ] **Step 3: Update the README sentence**

In `README.md`, replace "and opening a PR from the clipboard, a dropped link, or your recent and awaiting-review PRs on the start screen." with:

```markdown
and opening a PR from the clipboard, a dropped link, or the start screen's lists: PRs
awaiting your review, PRs you opened recently, and the open PRs of any repository you
choose to watch.
```

Keep the existing line breaks at or under the file's wrap width.

- [ ] **Step 4: Run every local gate**

```sh
swift format --in-place --recursive --parallel Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift
swiftlint lint --strict
swift build
swift test --enable-code-coverage
scripts/periphery.sh
swift test --sanitize=address --skip BenchmarkTests --skip BenchTests
```

Expected: every command exits 0. Address Sanitizer runs here because Task 9 added a task group.

- [ ] **Step 5: Check coverage of the touched files**

Run the coverage command from "Commands used throughout".
Expected: every file under `Views/Start/`, plus `Models/WatchedRepository.swift`, `Services/WatchedPullRequests.swift`, `Services/Preferences.swift`, `Services/AnonymousAPISource.swift`, `Views/PRSessionCommands.swift` and `Views/ContentView.swift`, is at 90.00% or above, and TOTAL is not below the figure on `main`.

- [ ] **Step 6: Commit and ship**

```sh
git add DESIGN.md README.md
git commit -m "Describe watched repositories in DESIGN.md and the README"
```

Continue with steps 4 to 8 of the `ship` skill: push, open the pull request, watch CI, squash-merge when green, remove the worktree.

---

## Spec coverage

| Spec section | Task |
|---|---|
| §1 Sidebar, detail pane, selection, welcome | 2, 3, 4 |
| §1 Rows and labels | 9, 10 |
| §1 States | 4 (review requests, recents, welcome), 10 (watched) |
| §2 Adding, suggestions, validation | 6, 9, 10 |
| §2 Removing and context menu | 9, 10 |
| §2 File menu | 11 |
| §3 Types | 6, 7 |
| §3 Fetching, bot filter, `hasMore` | 7, 8 |
| §3 Viewer login | 8, 9 |
| §3 Storage | 3, 9 |
| §3 Refresh and freshness | 9, 10 |
| §4 Failures | 8, 10 |
| §5 Security | 6, 10, 12 |
| §6 Code shape, file moves | 1, 2, 4 |
| §7 Testing | every task |
| §8 Documentation | 5, 12 |
| §9 Two pull requests | Parts 1 and 2 |
| §10 Opus 5.5 | header |
