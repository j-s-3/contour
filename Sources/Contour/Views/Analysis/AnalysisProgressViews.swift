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
/// hollow circle not started.
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
            case .pending:
                Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .frame(width: 14, height: 14)
    }
}

// MARK: - Toolbar indicator

/// "✦ Analyzing PR… 3 remaining" while the analysis fills in; "✓ Analysis complete" when it
/// finishes, fading to a bare check a few seconds later. Clicking it opens the details.
struct AnalysisIndicator: View {
    let state: AnalysisState
    let log: [PipelineProgressEntry]
    let metrics: AnalysisMetrics?
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
                AnalysisDetailsView(state: state, log: log, metrics: metrics, onRetry: onRetry)
            }
            .task(id: state.isComplete) {
                // Let the "complete" state be seen, then recede.
                settled = false
                guard state.isComplete, state.failedSections.isEmpty else { return }
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.easeOut(duration: 0.6)) { settled = true }
            }
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 6) {
            if !state.isComplete {
                WorkingMark()
                Text(state.revalidatingFrom != nil ? "Updating analysis…" : "Analyzing PR…")
                    .font(.callout)
                let remaining = state.remainingCount
                if remaining > 0 {
                    Text(verbatim: "\(remaining) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if !state.failedSections.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                let n = state.failedSections.count
                Text(verbatim: "\(n) \(n == 1 ? "section" : "sections") couldn't be analyzed").font(.callout)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                if !settled {
                    Text("Analysis complete").font(.callout).transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Details popover

/// What the indicator opens: the review sections and where each one is, then — for anyone
/// who wants them — the pipeline's own stages, the timings, and the raw log.
struct AnalysisDetailsView: View {
    let state: AnalysisState
    let log: [PipelineProgressEntry]
    let metrics: AnalysisMetrics?
    var onRetry: (PipelineStage) -> Void

    @State private var showPipeline = false
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ANALYSIS")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

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
            if status.failure != nil, let stage = section.stages.first(where: { state.status($0).failure != nil }),
               PipelineStage.analysis.contains(stage) {
                Button("Retry") { onRetry(stage) }.controlSize(.small)
            }
        }
    }

    private func subtitle(_ section: ReviewSection, _ status: StageStatus) -> String? {
        switch status {
        case .running(let detail): return detail ?? section.workingLabel
        case .failed(let message): return message
        case .stale: return "From the previous revision"
        case .pending: return "Waiting"
        case .done: return nil
        }
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
                    Text(metrics.elapsed(milestone).map { String(format: "%.1fs", $0) } ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
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
            if case .running(let detail?) = status {
                WorkingLine(text: "\(section.workingLabel.dropLast()) — \(detail)")
            } else {
                WorkingLine(text: status == .pending ? "Waiting to start…" : section.workingLabel)
            }
            Text("You can keep reviewing elsewhere; this fills in on its own.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A section whose analysis failed: says so, and offers a retry and a conversation instead.
/// The rest of the review is unaffected.
struct SectionFailedView: View {
    let section: ReviewSection
    let message: String
    var onRetry: () -> Void
    var onAsk: (() -> Void)?

    @State private var showMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(section.title) analysis failed", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary, .orange)
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
            DisclosureGroup("What went wrong", isExpanded: $showMessage) {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
            Text(verbatim: "Showing analysis from previous revision \(head.prefix(7))")
                .fontWeight(.medium)
            Text("·").foregroundStyle(.tertiary)
            WorkingLine(text: "Updating for new commits…", font: .caption)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.yellow.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Before the shell

/// The only full-window wait left: fetching the PR itself, usually a second or two. The
/// review replaces it as soon as there's a title and a diff to show.
struct OpeningView: View {
    let log: [PipelineProgressEntry]
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Opening PR…").font(.title3.weight(.medium))
            }
            if let last = log.last {
                Text(last.detail).font(.caption).foregroundStyle(.secondary)
            }
            Button(showLog ? "Hide log" : "Show log") { showLog.toggle() }
                .buttonStyle(.link)
                .font(.caption)
            if showLog {
                AnalysisLogView(log: log)
                    .frame(width: 560, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
