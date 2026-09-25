# Contour — making the PR review app harness-, tracker-, and auth-agnostic

Status: approved 2026-09-25. Supersedes the single-backend assumptions in
`DESIGN.md` §8, §10, and §16.

## Why

Contour is a fork of Aperture. Aperture was built against exactly one of
everything: `pi` as the AI backend, `gh` as the only way to reach GitHub, and
Jira (via `acli`) as the only issue tracker. Each of those was a reasonable MVP
shortcut and each is now a barrier to anyone who doesn't share that setup. The
fixtures and sample data were also modeled on a private PR, which
can't ship in a general-purpose tool.

This design introduces three seams and replaces the private sample content.
It deliberately does not expand MVP scope: posting reviews back to GitHub,
LSP-grade navigation, and sharded analysis stay deferred.

## Non-goals

- Holding any provider credential. Contour continues to shell out to already
  authenticated CLIs, or to use anonymous public APIs. The one exception the
  design explicitly rejected: a GitHub token in app config or Keychain.
- A harness plugin system. Two concrete conformers, chosen because both are
  installed and verifiable; a third is a code change, not a config file.
- Changing the analysis pipeline's stage structure or prompts, beyond making
  the issue-tracker stage generic.

## 1. Harness abstraction

`AnalysisService` currently hardcodes both pi's argv and pi's JSON event
schema. Both move behind `Harness`:

```swift
enum HarnessID: String, Codable, CaseIterable { case pi, claude }

enum HarnessEvent {
    case progress(String)    // human-readable tool-call line for the UI
    case finalText(String)   // the stage's final assistant message
}

protocol Harness: Sendable {
    var id: HarnessID { get }
    var executable: String { get }
    /// Full argv after the executable, including the prompt and context file.
    func arguments(prompt: String, contextFile: String, tier: AnalysisTier,
                   systemPrompt: String) throws -> [String]
    /// nil for lines this harness doesn't care about (heartbeats, hook noise).
    func interpret(_ line: String) -> HarnessEvent?
}
```

`AnalysisService` keeps what is genuinely shared — the mock short-circuit, the
grounding system prompt, defensive JSON extraction, the error type — and gains
a `harness` property. Everything pi-specific moves to `PiHarness`.

### Verified contract differences

Confirmed by running both CLIs, not inferred from documentation.

| Concern | `pi` | `claude` |
|---|---|---|
| Non-interactive | `-p` | `-p` |
| Stream format | `--mode json` | `--output-format stream-json --verbose` |
| Ephemeral session | `--no-session` | default under `-p` |
| Read-only tools | `--tools read,grep,find,ls` | `--allowedTools Read,Grep,Glob` |
| Effort tier | `--thinking low\|high` | `--effort low\|high` |
| System prompt | `--append-system-prompt` | `--append-system-prompt` |
| Context file | `@file` as its own argv token | contents inlined into the prompt |
| Progress event | `tool_execution_start`, `toolName`, `args.path` | `assistant` → `content[].tool_use`, `name`, `input.file_path` |
| Final text | `message_end` → last text block | `result` / `success` → `.result` |

Two details that cost real debugging time and are therefore load-bearing:

- pi resolves `@file` by scanning a raw argv token for a leading `@`, so the
  file reference and the prompt body must be **separate** arguments. Claude has
  no equivalent, so `ClaudeHarness` reads the context file and prepends its
  contents to the prompt. Both paths must deliver the same text to the model.
- Claude's stream carries `system/hook_started`, `system/hook_response`, and
  `rate_limit_event` lines interleaved with content. `interpret` returns nil for
  unknown types rather than failing.

### Untrusted-checkout hardening

Aperture wraps PR *text* in `<UNTRUSTED_PR_CONTENT>` but both harnesses
auto-discover `CLAUDE.md` / `AGENTS.md`, skills, hooks, and plugins **from the
checkout**. For a tool whose whole purpose is analyzing arbitrary pull requests
from the internet, those files are attacker-controlled content loaded as
instructions. Aperture's §16 does not cover this.

Every invocation therefore disables project-resident customization:

- pi: `--no-context-files --no-extensions --no-skills`
- claude: `--restricted --safe-mode`

`--safe-mode` disables CLAUDE.md, skills, plugins, hooks, MCP servers, and
custom agents while leaving auth and model selection intact. `--bare` was
rejected: it forces `ANTHROPIC_API_KEY`-only auth and would break users on
subscription auth. `--restricted` additionally drops command-running tools and
WebFetch and confines file tools to the working directory.

## 2. GitHub access

`gh` is preferred when present; the anonymous REST API is the fallback, so a
public PR works on a machine with nothing but `git`.

`PRSource` protocol, two conformers:

- `GHCLISource` — today's `gh pr view --json` / `gh pr diff` code, moved.
- `PublicAPISource` — `URLSession` against `api.github.com`: the PR itself,
  `/files` (paginated), `/commits`, `/issues/{n}/comments`, `/pulls/{n}/reviews`,
  and the diff via `Accept: application/vnd.github.v3.diff`.

`GitHubService` becomes the façade that selects one. Selection order: `gh` on
PATH *and* `gh auth status` clean → `GHCLISource`; otherwise `PublicAPISource`.
A 404 or 403 from the anonymous path means the repo is private, and the error
says so in those words, naming `gh auth login` as the fix. Rate-limit 403s are
distinguished by `X-RateLimit-Remaining: 0` and reported as a rate limit
(anonymous is 60/hour, roughly 20 PRs).

`RepoContextService` drops `gh repo clone` for `git clone https://github.com/…`.
Git's credential helper — which `gh` itself installs — covers private repos, so
one checkout path serves both cases and `gh` leaves that file entirely.

**Known risk, accepted:** with `gh` preferred, the REST path is the less
exercised one, and it is exactly the path a new user hits. Mitigated two ways:
a Settings control (Auto / Prefer gh / Anonymous API only) that forces it on
demand, and a shared conformance test suite asserting both sources produce
field-for-field identical `RawPRContext` from captured fixtures.

## 3. Issue tracker

```swift
enum TrackerID: String, Codable, CaseIterable { case github, jira, none }

struct IssueRef: Hashable, Sendable { var id: String; var tracker: TrackerID }

struct TicketInfo: Codable, Hashable, Sendable {
    var kind: TrackerID
    var key: String        // "#1234" or "PROJ-1234"
    var summary: String
    var description: String
    var url: String
}

protocol IssueTracker: Sendable {
    func reference(in context: RawPRContext) -> IssueRef?
    func fetch(_ ref: IssueRef) async -> TicketInfo?   // best-effort, never throws
}
```

- `GitHubIssueTracker` is the default. It parses `#123`, `owner/repo#123`, and
  closing keywords (`fixes`/`closes`/`resolves`) from title, body, branch names,
  and commit messages, then fetches through the same `PRSource`. Issue bodies
  are already markdown, so no ADF flattening is needed.
- `JiraTracker` is today's `acli` code, offered only when `acli` is on PATH and
  the user has enabled it. Absent or disabled, it never runs.

The best-effort contract is unchanged and load-bearing: a missing, unreachable,
or unparseable ticket must never fail PR analysis.

Model changes: `JiraTicketInfo` → `TicketInfo`; `PRSummary.jiraTicket` →
`PRSummary.ticket`; pipeline stage `.jira` → `.ticket` labeled "Checking issue
tracker"; `PromptBuilder.eli5Prompt` takes `TicketInfo?` and speaks generically
("the linked issue"). The graph's on-disk shape changes, so
`AnalysisPipeline.pipelineVersion` bumps 3 → 4, which correctly invalidates
every cached analysis from the old schema.

## 4. Preferences, Settings, and first-run wizard

`EnvironmentProbe` resolves each external tool once and returns

```swift
struct ToolStatus: Sendable {
    var name: String
    var path: String?          // nil = not installed
    var version: String?
    var authenticated: Bool?   // nil = not applicable
    var detail: String         // one line for the UI
}
```

so both surfaces show the same truth, and preflight failures surface before the
pipeline runs rather than deep inside it.

`Preferences` is `@Observable`, persisted in `UserDefaults`, with env-var
overrides for tests and scripting. Precedence: **env > stored > detected**.

| Key | Env override | Values |
|---|---|---|
| harness | `CONTOUR_HARNESS` | `pi`, `claude` |
| tracker | `CONTOUR_TRACKER` | `github`, `jira`, `none` |
| githubAccess | `CONTOUR_GITHUB_ACCESS` | `auto`, `gh`, `anonymous` |
| model override per tier | — | free text, empty = harness default |

**Settings scene** (⌘,): harness picker with uninstalled options disabled and
detected versions shown; per-tier model overrides; GitHub access mode; tracker
picker with the Jira row disabled and labeled "acli not found" when absent.

**First-run wizard**, shown while `hasCompletedOnboarding` is false: (1) what
Contour does; (2) a live environment check — `git`, harness, `gh` marked
*"only needed for private PRs"*, `acli` marked *"enable Jira?"* — with a
re-probe button; (3) paste your first PR URL. If both harnesses are installed
and nothing is stored, the wizard asks rather than picking silently.

## 5. Replacing private sample content

- `MockAnalysisFixtures` and `SampleData` are regenerated from a real, public
  OSS PR whose body closes a GitHub issue, so the fixture exercises
  `GitHubIssueTracker` as well. Captured from a genuine pipeline run rather than
  invented, so the fixture keeps matching real output shapes.
- `PromptBuilder`'s component-naming examples become generic.
- `JiraAndCacheTests` → `TrackerAndCacheTests`, with generic keys.
- `README.md` and `DESIGN.md` §8/§10/§16 rewritten — each currently asserts a
  premise (pi-only, gh-required, Jira-only) that this design makes false.

## 6. Testing

TDD throughout. The suites that carry the design's weight:

1. **Harness contract tests** — captured real JSONL from both CLIs replayed
   through `interpret`, asserting progress lines and final text. This is what
   keeps the abstraction honest without network or model spend.
2. **`PRSource` parity** — one shared suite run against both a captured `gh`
   fixture and a captured REST fixture, asserting identical `RawPRContext`.
3. **Issue-reference detection** — table-driven over titles, branches, bodies,
   and commits, including no-match and `#123` vs `PROJ-123` precedence.
4. **Preferences precedence** — env beats stored beats detected.
5. **Integration**, gated behind `RUN_CONTOUR_INTEGRATION=1`, re-pointed at a
   public PR so it needs no private access, and parameterized over harness:
   `RUN_CONTOUR_INTEGRATION=1 CONTOUR_HARNESS=claude swift test`.

## 7. Order of work

Each step keeps the build and tests green.

1. Fork and rename (done — commit 12ec9a9)
2. Harness seam
3. Issue-tracker seam
4. `PRSource` seam and the `git clone` switch
5. Preferences, Settings scene, first-run wizard
6. Fixture regeneration and documentation rewrite
