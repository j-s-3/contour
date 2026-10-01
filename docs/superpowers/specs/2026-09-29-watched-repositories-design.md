# Contour — watched repositories and the start screen as a source browser

Status: approved 2026-09-29. Amends `DESIGN.md` §4.1a (Welcome).

## Why

The start screen offers review work from two places: PRs where the user's review
was requested, and PRs they opened recently. Neither covers a repository the user
cares about but wasn't asked to review in. Finding that work means leaving Contour
for GitHub, picking a PR, and pasting its URL back.

Watching a repository puts its open pull requests on the start screen, so picking
up unrequested review work starts where a review session already starts.

The current screen can't take a third list. It is a centered hero over two
five-row columns capped at 760pt, and a watched repository needs ten rows plus a
way to switch between repositories. So the screen is restructured rather than
extended.

## Decisions taken during brainstorming

| Question | Decision |
|---|---|
| What watching is for | Finding review work |
| Which PRs | Open only, newest first by creation date, 10 per repository |
| Left out | PRs authored by bots. Drafts and the user's own PRs stay, labelled |
| What "switch between" means | Switching which watched repository is shown on the start screen |
| Expected scale | 2 to 5 watched repositories |
| Adding and removing | On the start screen, and from the File menu while a PR is open |
| Layout | A sidebar of sources with one list beside it |

## Non-goals

- Switching pull requests from inside an open review.
- Merged or closed pull requests.
- Notifications, badges or unread state for new pull requests.
- Configurable filters or sort order.
- A Settings pane for the watch list.
- Persisting fetched pull request lists to disk.
- Using GitHub's own watch or subscription state. Watching is local to Contour.

## 1. The screen

The start screen becomes a two-pane browser built on `NavigationSplitView`, the
same container as the review shell.

```
┌──────────────────────┬──────────────────────────────────────────────┐
│ ◎ Contour            │ [ Paste a GitHub pull request URL…  ] [Open] │
│                      │                                              │
│ Awaiting review    3 │ ACME/API · OPEN PULL REQUESTS  updated now ↻ │
│ Recently opened      │ Retry webhook deliveries with backoff        │
│                      │ #1284 · mwright · opened 2 hours ago         │
│ WATCHED              │ Move rate limiter state into Redis           │
│ acme/api         10+ │ #1283 · akhan · opened 5 hours ago  [draft]  │
│ acme/web           7 │ …                                            │
│ acme/infra         2 │                                              │
│ + Watch a repository…│                                              │
└──────────────────────┴──────────────────────────────────────────────┘
```

### Sidebar

Sources, in order:

1. **Awaiting your review**, present only when `gh` can answer, as today.
2. **Recently opened**.
3. A **Watched** group with one entry per watched repository, in the order they
   were added, followed by **+ Watch a repository…**.

Each entry with rows shows a count. A watched repository's count is the number of
rows listed, or `10+` when more open pull requests exist than the ten shown. A
repository whose fetch failed shows `!` in place of the count.

The sidebar header carries the small Contour mark and the name. The mark keeps its
matched-geometry identity, so it still glides to the centre and starts resolving
when a pull request opens. The opening animation in §4.1a is unchanged.

### Detail pane

Top to bottom: the URL field with its paste and Open buttons, the clipboard offer,
the "Load test data" button in mock mode, then the selected source's list. The URL
field, clipboard handling, drop handling and focus behaviour are unchanged from
today.

The list header names the source. For a watched repository it also shows when the
list was fetched and a refresh button.

### Rows

Review-request and recent rows keep their current content.

A watched pull request row shows the title, then `#1284 · mwright · opened 2 hours
ago`. The repository is omitted because the list header names it. Small labels
follow where they apply:

| Label | When |
|---|---|
| `draft` | The pull request is a draft |
| `yours` | The author is the signed-in user. Requires `gh`; never shown anonymously |
| `review requested` | The pull request also appears in the review-request list |

Clicking a row opens the pull request exactly as the existing rows do.

### Selection

The selected source is remembered between launches. With nothing remembered, or
when the remembered source no longer exists, selection falls back to the first
available of: Awaiting your review, Recently opened, the first watched
repository.

### States

| State | Detail pane |
|---|---|
| No source has any rows and nothing is watched | Today's welcome: large mark, "Contour", the proposition, URL field |
| Selected source is loading | URL field, list header, a quiet progress indicator |
| Watched repository has no open pull requests | "No open pull requests." |
| Every one of the newest 30 open pull requests is from a bot | "The newest 30 open pull requests are all automated." |
| Watched repository could not be read | The failure message (§4) and **Try again** |
| Recently opened is empty | "Pull requests you open will appear here." |
| Awaiting your review is empty | "Nothing is waiting for your review." |

Every list shows at most 10 rows.

The mark stays still in the welcome state, per §4.1a.

## 2. Managing the watch list

### Adding on the start screen

**+ Watch a repository…** opens a popover with one text field and a list of
suggestions.

The field accepts `owner/repo`, a repository URL, or a pull request URL. Input is
parsed into an owner and a name, each validated against GitHub's allowed
characters (letters, digits, `-`, `_`, `.`; an owner cannot start with `-`). Input
that does not validate disables the confirm button. Validation is what stops a
value such as `--flag` reaching `gh` as an argument.

Suggestions are the distinct repositories in the recent pull request index that
are not already watched, most recent first, at most five.

Adding a repository selects it and fetches it. Adding one that is already watched
selects the existing entry.

### Removing and other actions

Right-clicking a watched repository offers **Refresh**, **Open Repository on
GitHub** and **Stop Watching owner/repo**. Removing the selected repository moves
selection by the fallback rule in §1.

### From an open pull request

The File menu gains one item after "Copy Link to Pull Request":
**Watch owner/repo**, or **Stop Watching owner/repo** when it is already watched.
It is disabled when no pull request is open.

## 3. Data

### Types

```swift
struct WatchedRepository: Codable, Equatable, Identifiable, Sendable {
    var owner: String
    var name: String
    var id: String { "\(owner)/\(name)" }
    static func parse(_ input: String) -> WatchedRepository?
}

struct WatchedPullRequest: Equatable, Identifiable, Sendable {
    var url: String
    var number: Int
    var title: String
    var author: String
    var isDraft: Bool
    var createdAt: Date?
}

struct WatchedPullRequestList: Equatable, Sendable {
    var pullRequests: [WatchedPullRequest]
    var hasMore: Bool
    var fetchedAt: Date
}
```

### Fetching

`WatchedPullRequests` follows the shape of `ReviewRequests`: an async `fetch` that
chooses a transport from `GitHubAccessMode`, and pure `parse` functions.

| Access | Call | Bot signal |
|---|---|---|
| `gh` | `gh pr list -R owner/repo --state open --limit 30 --json number,title,url,author,isDraft,createdAt` | `author.is_bot` |
| Anonymous | `GET /repos/{owner}/{repo}/pulls?state=open&sort=created&direction=desc&per_page=30` | `user.type == "Bot"` |

`auto` resolves as it does elsewhere: `gh` when installed, anonymous otherwise.

Both transports fetch 30, remove bots, sort newest first and keep 10. The two
transports spell a bot's login differently: `gh` reports `app/dependabot`, the
REST API reports `dependabot[bot]`. A login with the `app/` prefix or the `[bot]`
suffix also counts as a bot, covering responses that omit the flag or type. Both
shapes were checked against `cli/cli` on 2026-09-29.
`hasMore` is true when more than ten remain after filtering, or when the response
was a full page of 30.

The signed-in login for the `yours` label comes from `gh api user --jq .login`,
fetched once per launch and only under `gh` access.

### Storage

`Preferences` gains two stored values in `UserDefaults`:

- `watchedRepositories`: the ordered list of `owner/repo` strings.
- `lastStartSource`: the remembered selection.

Neither has an environment override. They are not in the analysis cache, so
clearing the cache keeps the watch list.

Fetched lists live in memory in `StartScreenModel`, which `ContentView` owns so it
outlives the start screen view. Returning from a review with ⌘W shows the lists
at once. A cold launch shows the loading state until the first fetch lands.

### Refresh

- When the start screen appears, every watched repository is fetched
  concurrently, unless its list is fresh.
- When the app becomes active, the same rule applies.
- A list is fresh for 2 minutes under `gh` and for 10 minutes anonymously.
  Anonymous access shares GitHub's 60 requests per hour with opening pull
  requests.
- **Refresh** and **Try again** always fetch, for that repository only.

A refresh keeps the rows on screen until the new list arrives. A failed refresh of
a repository that already has rows keeps them and records the failure.

## 4. Failures

Each failure belongs to one repository and never hides another source.

| Cause | Message |
|---|---|
| Not found or private | "Couldn't list pull requests for owner/repo. It's private or doesn't exist. Sign in with the GitHub CLI to watch private repositories." |
| Anonymous rate limit | "Couldn't list pull requests for owner/repo. GitHub's anonymous limit is used up. Try again after 3:40 PM." |
| Anything else | "Couldn't list pull requests for owner/repo." |

The sign-in sentence appears only under anonymous access. Raw `gh` stderr and
HTTP bodies go to the technical log.

## 5. Security

- Pull request titles and author logins are untrusted. They are rendered as
  verbatim text and never reach a harness prompt.
- Repository input is validated before it is stored or passed to `gh` (§2).
- No new credential is held. Private repositories are readable only through an
  already authenticated `gh`.
- The harness invariants in `CLAUDE.md` are untouched; this feature makes no
  harness call.

## 6. Code shape

| File | Change |
|---|---|
| `Models/WatchedRepository.swift` | New. The type and its parser |
| `Services/WatchedPullRequests.swift` | New. Fetch, both parsers, bot filter |
| `Services/Preferences.swift` | Two stored values |
| `Views/Start/StartScreenModel.swift` | New. `@Observable`, `@MainActor`: sources, selection, per-repository load state, freshness, add and remove |
| `Views/Start/StartScreenView.swift` | New. The split view, sidebar and detail pane |
| `Views/Start/WatchRepositoryPopover.swift` | New. The add popover |
| `Views/Start/PullRequestRows.swift` | `PullRequestList`, `PullRequestRow` and the clipboard row move here from `OnboardingView.swift` |
| `Views/Analysis/AnalyzingView.swift`, `FailedView.swift` | Moved out of `OnboardingView.swift` unchanged |
| `Views/OnboardingView.swift` | Removed once its contents have moved |
| `Views/ContentView.swift` | Owns the model; shows `StartScreenView` for the idle phase |
| `Views/PRSessionCommands.swift` | The watch toggle |

`OnboardingViewLogic` keeps its clipboard and paste functions and is renamed
`StartScreenLogic`. Logic stays out of view bodies: source ordering, selection
fallback, counts, freshness, label choice and suggestion ranking are pure
functions on the model or beside it.

The repository follows a no-comments convention; these types carry none.

## 7. Testing

- **Parsers.** Fixtures captured from real `gh pr list` output and from the REST
  endpoint, against a public repository, with provenance added to
  `Tests/ContourTests/Fixtures/README.md`. Cases: bots removed by flag, by
  `app/` prefix and by `[bot]` suffix, drafts kept, ordering, `hasMore` on both conditions, malformed and
  empty input.
- **Repository parsing.** `owner/repo`, repository URLs, pull request URLs,
  trailing slashes and `.git`, and rejected input including a leading `-`.
- **Model.** Injected loaders and an injected clock: selection fallback,
  remembered selection, add and remove, duplicate add, freshness under both access
  modes, a failure isolated to one repository, rows kept across a failed refresh.
- **Preferences.** Round trip through a scratch `UserDefaults` suite.
- **Views.** Hosted in a window with injected loaders, as
  `OnboardingViewHostingTests` does, covering each state in §1.
- **Menu.** The toggle's title and enabled state, through the existing
  `PRSessionCommandsLogic` pattern.

Every new or touched file stays at 90% line coverage or above, and the overall
figure does not drop.

## 8. Documentation

- `DESIGN.md` §4.1a: replace the Welcome paragraph with the source browser and
  note the mark's new resting place.
- `README.md`: the sentence that lists the ways to open a pull request.

Neither `README.md` nor `site/` has a screenshot of the start screen today, so
none needs replacing. The new screen is checked visually during implementation
with an in-process window snapshot.

## 9. Order of work

Two pull requests, each shippable alone:

1. **Restructure the start screen.** The split view with the two existing sources,
   the file moves, remembered selection, the welcome state. No watched
   repositories yet.
2. **Watched repositories.** Types, fetching, storage, the Watched group, the add
   popover, the context menu, the File menu toggle and documentation.

## 10. Implementation notes

Implementation is to be carried out with Claude Opus 5.5 (`claude-opus-5-5`), at
the user's request. Each pull request goes through the repository's `ship`
workflow.
