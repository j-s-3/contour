import SwiftUI

// Progressive opening (§ progressive analysis): the review appears as soon as the PR has been
// fetched and fills in while the reviewer works. These are the pieces that say how far along
// that is — quietly. The best progress indicator is content appearing, so none of them ever
// take focus, move the reviewer, or cover what they're reading.

/// The one sparkle glyph every "still working" line uses, so they read as one voice.
/// Pulses with a symbol effect rather than a repeating animation: a `repeatForever`
/// animation started on appear also animates the view's own layout, which in a toolbar
/// visibly flings the glyph in from wherever it was first laid out.
struct WorkingMark: View {
    var body: some View {
        Image(systemName: "sparkle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityHidden(true)
    }
}

/// "✦ Understanding the change…" — a placeholder line for content still being produced.
struct WorkingLine: View {
    let text: String
    var font: Font = .callout

    var body: some View {
        HStack(spacing: 7) {
            WorkingMark()
            Text(text).font(font).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Status glyph for a stage or section: ✓ done, spinner running, ⚠ failed, clock stale,
/// ⏹ stopped, hollow circle not started.
struct StageStatusGlyph: View {
    let status: StageStatus

    var body: some View {
        Group {
            switch status {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .running:
                ProgressView().controlSize(.mini)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .stale:
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
            case .stopped:
                Image(systemName: "stop.circle").foregroundStyle(.secondary)
            case .pending:
                Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .frame(width: 14, height: 14)
    }
}

// MARK: - Toolbar indicator

/// "Analyzing PR… 3 remaining" beside the resolving Contour mark while the analysis fills
/// in; "Analysis complete" (or "Opened saved analysis") when it finishes, fading to the bare
/// mark a few seconds later. Clicking it opens the details, which is also where the
/// analysis can be stopped.
struct AnalysisIndicator: View {
    let state: AnalysisState
    let log: [PipelineProgressEntry]
    let metrics: AnalysisMetrics?
    var refCheck: RefCheck?
    var onStop: (() -> Void)?
    var onRetry: (PipelineStage) -> Void

    @State private var showDetails = false
    @State private var settled = false

    var body: some View {
        Button { showDetails.toggle() } label: { label }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(settled ? 0 : 0.1), in: Capsule())
            .help("Analysis progress — click for details")
            .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                AnalysisDetailsView(state: state, log: log, metrics: metrics, refCheck: refCheck, onStop: onStop, onRetry: onRetry)
            }
            .task(id: state.isComplete) {
                // Let the "complete" state be seen, then recede.
                settled = false
                guard state.isComplete, state.failedSections.isEmpty, state.stoppedSections.isEmpty else { return }
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.easeOut(duration: 0.6)) { settled = true }
            }
    }

    /// The Contour mark from the opening screen, carried on into the toolbar: it resolves
    /// ring by ring as stages settle, and is whole when the analysis is.
    @ViewBuilder
    private var label: some View {
        HStack(spacing: 6) {
            ContourMarkView(resolution: AnalysisResolution.target(state: state))
                .frame(height: 13)
                .animation(.easeInOut(duration: 0.8), value: AnalysisResolution.target(state: state))
            switch AnalysisIndicatorLabel.compute(state: state, settled: settled) {
            case .analyzing(let text, let remaining):
                Text(text).font(.callout)
                if remaining > 0 {
                    Text(verbatim: "\(remaining) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            case .stopped:
                // Stopping is the reviewer's own, most recent act, so it's what the
                // indicator reports even if a section had also failed.
                StageStatusGlyph(status: .stopped)
                Text("Analysis stopped").font(.callout)
            case .failed(let text):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(verbatim: text).font(.callout)
            case .complete(let text):
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .transition(.opacity)
            case .none:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
    }
}

/// What `AnalysisIndicator`'s label shows for a given state, decided once so the view body
/// only has to draw it. `settled` is the indicator's own local fade-out timer: true once
/// "Analysis complete" has had its few seconds on screen and is receding to the bare mark.
enum AnalysisIndicatorLabel: Equatable {
    case analyzing(text: String, remaining: Int)
    case stopped
    case failed(text: String)
    case complete(text: String)
    case none

    /// Stopping is the reviewer's own, most recent act, so it's reported even if a section
    /// also failed; a failure otherwise outranks the transient "complete" message, which
    /// itself only shows before `settled` fades it back to the bare mark.
    nonisolated static func compute(state: AnalysisState, settled: Bool) -> AnalysisIndicatorLabel {
        if !state.isComplete {
            let text = state.revalidatingFrom != nil ? "Updating analysis…" : "Analyzing PR…"
            return .analyzing(text: text, remaining: state.remainingCount)
        }
        if !state.stoppedSections.isEmpty {
            return .stopped
        }
        if !state.failedSections.isEmpty {
            let n = state.failedSections.count
            return .failed(text: "\(n) \(n == 1 ? "section" : "sections") couldn't be analyzed")
        }
        if !settled {
            return .complete(text: state.fromCache ? "Opened saved analysis" : "Analysis complete")
        }
        return .none
    }
}

// MARK: - Details popover

/// What the indicator opens: the review sections and where each one is, then — for anyone
/// who wants them — the pipeline's own stages, the timings, and the raw log.
struct AnalysisDetailsView: View {
    let state: AnalysisState
    let log: [PipelineProgressEntry]
    let metrics: AnalysisMetrics?
    var refCheck: RefCheck?
    /// Nil where stopping isn't offered; the button itself shows only while there's
    /// analysis left to stop.
    var onStop: (() -> Void)?
    var onRetry: (PipelineStage) -> Void

    @State private var showPipeline = false
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ANALYSIS")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if let onStop, state.canStop {
                    Button(action: onStop) {
                        Label("Stop analysis", systemImage: "stop.fill")
                    }
                    .controlSize(.small)
                    .help("Stop the remaining analysis. What's already here stays; each stopped section can be retried on its own.")
                }
            }

            if let head = state.revalidatingFrom {
                Label {
                    Text(verbatim: "Showing analysis from previous revision \(head.prefix(7)) while this one is analyzed")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(ReviewSection.allCases) { section in
                    sectionRow(section)
                }
            }

            if let refCheck, refCheck.checked > 0 {
                RefCheckView(check: refCheck)
            }

            Divider()

            DisclosureGroup("Pipeline details", isExpanded: $showPipeline) {
                VStack(alignment: .leading, spacing: 12) {
                    PipelineStagesView(state: state)
                    if let metrics { MetricsView(metrics: metrics) }
                }
                .padding(.top, 8)
            }
            .font(.callout)

            DisclosureGroup("Show log", isExpanded: $showLog) {
                AnalysisLogView(log: log)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 8)
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 420)
    }

    private func sectionRow(_ section: ReviewSection) -> some View {
        let status = state.sectionStatus(section)
        let retryStage = state.retryStage(for: section)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            StageStatusGlyph(status: status)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.callout)
                if let subtitle = subtitle(section, status) {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            // A stopped context section is the checkout itself: its Retry reopens the PR.
            if let stage = retryStage, Self.showsRetryButton(stage: stage, status: status) {
                Button("Retry") { onRetry(stage) }.controlSize(.small)
            }
        }
    }

    /// Whether a section row with a retry-eligible stage (`AnalysisState.retryStage`) actually
    /// shows the button: every analysis stage does once it's retryable, but a context
    /// (plumbing) stage's Retry reopens the whole PR, so it only appears once that section has
    /// genuinely stopped rather than merely having a retryable stage in the abstract.
    nonisolated static func showsRetryButton(stage: PipelineStage, status: StageStatus) -> Bool {
        PipelineStage.analysis.contains(stage) || status == .stopped
    }

    private func subtitle(_ section: ReviewSection, _ status: StageStatus) -> String? {
        Self.subtitle(section, status)
    }

    /// The second line under a section's status glyph. Pulled out of the view body so it's
    /// directly testable, per the "views should be thin" principle.
    nonisolated static func subtitle(_ section: ReviewSection, _ status: StageStatus) -> String? {
        switch status {
        case .running(let detail): return detail ?? section.workingLabel
        case .failed(let message): return message
        case .stale: return "From the previous revision"
        case .stopped: return "Stopped"
        case .pending: return "Waiting"
        case .done: return nil
        }
    }
}

/// Whether the code the analysis cites is really there (§18, `CodeRefVerifier`): "All 41
/// references verified", or how many couldn't be and which. Those were dropped from the
/// review, so this is the only place the reviewer learns the model cited code that isn't.
struct RefCheckView: View {
    let check: RefCheck

    @State private var showUnresolved = false

    var body: some View {
        if check.unresolvedCount == 0 {
            Label {
                Text(verbatim: Self.headline(check))
            } icon: {
                Image(systemName: "checkmark.seal").foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            DisclosureGroup(isExpanded: $showUnresolved) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(check.unresolved, id: \.self) { ref in
                        Text(ref)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let overflow = Self.overflowText(check) {
                        Text(verbatim: overflow)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text("These were left out of the review, and anything resting only on them is marked low confidence.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.top, 4)
            } label: {
                Label {
                    Text(verbatim: Self.headline(check))
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .font(.caption)
        }
    }

    /// The summary line: every reference verified, or how many of how many weren't.
    nonisolated static func headline(_ check: RefCheck) -> String {
        check.unresolvedCount == 0
            ? "All \(check.checked) code references verified"
            : "\(check.unresolvedCount) of \(check.checked) code references couldn't be verified"
    }

    /// "and N more" once the sample of listed refs (`RefCheck.sampleLimit`) is smaller than
    /// the true unresolved count; nil once every unresolved ref is already listed.
    nonisolated static func overflowText(_ check: RefCheck) -> String? {
        let extra = check.unresolvedCount - check.unresolved.count
        return extra > 0 ? "and \(extra) more" : nil
    }
}

/// The pipeline as the engine sees it — the old full-screen rail, now a detail. Stages run
/// in parallel, so each carries its own status rather than a single position.
struct PipelineStagesView: View {
    let state: AnalysisState

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(PipelineStage.allCases, id: \.self) { stage in
                HStack(spacing: 4) {
                    StageStatusGlyph(status: state.status(stage))
                    Text(stage.shortLabel).font(.caption)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.08), in: Capsule())
                .help(stage.rawValue)
            }
        }
    }
}

/// Time to each milestone for this PR — the numbers progressive opening is judged by.
struct MetricsView: View {
    let metrics: AnalysisMetrics

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
            ForEach(LatencyMilestone.allCases, id: \.self) { milestone in
                GridRow {
                    Text(milestone.label)
                        .font(.caption.weight(milestone == .usefulOverview ? .semibold : .regular))
                    Text(Self.elapsedText(metrics, milestone))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "12.3s" once a milestone has landed, an em dash while it's still to come.
    nonisolated static func elapsedText(_ metrics: AnalysisMetrics, _ milestone: LatencyMilestone) -> String {
        metrics.elapsed(milestone).map { String(format: "%.1fs", $0) } ?? "—"
    }
}

/// The technical log: every step and tool call, verbatim. For diagnosing stalls and failed
/// model calls, never the primary way to follow progress.
struct AnalysisLogView: View {
    let log: [PipelineProgressEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(log) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.stage)
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .leading)
                                .lineLimit(1)
                            Text(entry.detail)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .id(entry.id)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear { if let last = log.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            .onChange(of: log.count) { _, _ in
                if let last = log.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

// MARK: - In a section

/// A lens whose analysis hasn't produced anything yet: what's known so far, and what's being
/// worked on — never a blank screen or a disabled one.
struct SectionPendingView: View {
    let section: ReviewSection
    let status: StageStatus
    /// One line of what is already known, when there is something ("Input → Content
    /// Inspection → Rendering").
    var known: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            if let known, !known.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What the change does, so far").font(.caption).foregroundStyle(.tertiary)
                    Text(known).font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
            }
            WorkingLine(text: Self.workingText(section: section, status: status))
            Text("You can keep reviewing elsewhere; this fills in on its own.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The working line's text: a running stage's own detail folds onto the section's working
    /// label ("Understanding the change…" plus "2 files inspected" becomes "Understanding the
    /// change — 2 files inspected", the ellipsis dropped since the detail continues the
    /// sentence), "Waiting to start…" before anything has run, or the plain working label
    /// otherwise.
    nonisolated static func workingText(section: ReviewSection, status: StageStatus) -> String {
        if case .running(let detail?) = status {
            return "\(section.workingLabel.dropLast()) — \(detail)"
        }
        return status == .pending ? "Waiting to start…" : section.workingLabel
    }
}

/// A section whose analysis failed: says what didn't happen, and offers a retry and a
/// conversation instead. The rest of the review is unaffected. `message` is the
/// reviewer-facing line (`PipelineStage.failureMessage(for:)`); the raw response and stderr
/// stay behind "Show log" in the analysis details, never here.
struct SectionFailedView: View {
    let section: ReviewSection
    let message: String
    var onRetry: () -> Void
    var onAsk: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(section.title) analysis failed", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary, .orange)
            Text(message)
                .font(.callout)
                .frame(maxWidth: 640, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("Everything else in this review is still available.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Retry", action: onRetry)
                    .keyboardShortcut(.defaultAction)
                if let onAsk {
                    Button("Ask about \(section.title.lowercased())…", action: onAsk)
                }
            }
            Text("The technical details are in the analysis log — click the analysis status in the toolbar, then Show log.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 640, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A section the reviewer stopped before it produced anything: says so, and offers to
/// resume just this section. The rest of the review is unaffected.
struct SectionStoppedView: View {
    let section: ReviewSection
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(section.title) analysis stopped", systemImage: "stop.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary, .secondary)
            Text("Analysis was stopped before this section was ready. Everything that finished is still available.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetry)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "⏹ Stopped · Retry" floating at the bottom of a lens that was stopped partway: what
/// arrived before the stop stays, and this says there may have been more.
struct SectionStoppedPill: View {
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            StageStatusGlyph(status: .stopped)
            Text("Stopped before this finished").foregroundStyle(.secondary)
            Button("Retry", action: onRetry).buttonStyle(.link)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .padding(.bottom, 14)
        .transition(.opacity)
    }
}

/// "✦ 2 decisions found · still looking" floating at the bottom of a lens that already has
/// content but isn't finished. It overlays rather than inserts, so nothing the reviewer is
/// reading moves when it appears or goes.
struct SectionProgressPill: View {
    let text: String

    var body: some View {
        WorkingLine(text: text, font: .caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .padding(.bottom, 14)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

/// Across the top of every lens while slices from an earlier revision are on screen, so
/// nothing stale is read as a conclusion about the current code.
struct RevalidationBanner: View {
    let head: String
    /// False once nothing is running to replace it — the analysis was stopped.
    var updating = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
            Text(verbatim: "Showing analysis from previous revision \(head.prefix(7))")
                .fontWeight(.medium)
            if updating {
                Text("·").foregroundStyle(.tertiary)
                WorkingLine(text: "Updating for new commits…", font: .caption)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.yellow.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}
