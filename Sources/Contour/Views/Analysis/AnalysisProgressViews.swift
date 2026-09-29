import SwiftUI

struct WorkingMark: View {
    var body: some View {
        Image(systemName: "sparkle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityHidden(true)
    }
}

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
        Button {
            showDetails.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(settled ? 0 : 0.1), in: Capsule())
        .help("Analysis progress — click for details")
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            AnalysisDetailsView(
                state: state, log: log, metrics: metrics, refCheck: refCheck, onStop: onStop, onRetry: onRetry)
        }
        .task(id: state.isComplete) {
            settled = false
            guard state.isComplete, state.failedSections.isEmpty, state.stoppedSections.isEmpty else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.6)) { settled = true }
        }
    }

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

enum AnalysisIndicatorLabel: Equatable {
    case analyzing(text: String, remaining: Int)
    case stopped
    case failed(text: String)
    case complete(text: String)
    case none

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

struct AnalysisDetailsView: View {
    let state: AnalysisState
    let log: [PipelineProgressEntry]
    let metrics: AnalysisMetrics?
    var refCheck: RefCheck?
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
                    .help(
                        "Stop the remaining analysis. What's already here stays; each stopped section can be retried on its own."
                    )
                }
            }

            if let head = state.revalidatingFrom {
                Label {
                    Text(
                        verbatim: "Showing analysis from previous revision \(head.prefix(7)) while this one is analyzed"
                    )
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
            if let stage = retryStage, Self.showsRetryButton(stage: stage, status: status) {
                Button("Retry") { onRetry(stage) }.controlSize(.small)
            }
        }
    }

    nonisolated static func showsRetryButton(stage: PipelineStage, status: StageStatus) -> Bool {
        PipelineStage.analysis.contains(stage) || status == .stopped
    }

    private func subtitle(_ section: ReviewSection, _ status: StageStatus) -> String? {
        Self.subtitle(section, status)
    }

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
                    Text(
                        "These were left out of the review, and anything resting only on them is marked low confidence."
                    )
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

    nonisolated static func headline(_ check: RefCheck) -> String {
        check.unresolvedCount == 0
            ? "All \(check.checked) code references verified"
            : "\(check.unresolvedCount) of \(check.checked) code references couldn't be verified"
    }

    nonisolated static func overflowText(_ check: RefCheck) -> String? {
        let extra = check.unresolvedCount - check.unresolved.count
        return extra > 0 ? "and \(extra) more" : nil
    }
}

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

    nonisolated static func elapsedText(_ metrics: AnalysisMetrics, _ milestone: LatencyMilestone) -> String {
        metrics.elapsed(milestone).map { String(format: "%.1fs", $0) } ?? "—"
    }
}

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

struct SectionPendingView: View {
    let section: ReviewSection
    let status: StageStatus
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

    nonisolated static func workingText(section: ReviewSection, status: StageStatus) -> String {
        if case .running(let detail?) = status {
            return "\(section.workingLabel.dropLast()) — \(detail)"
        }
        return status == .pending ? "Waiting to start…" : section.workingLabel
    }
}

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
            Text(
                "The technical details are in the analysis log — click the analysis status in the toolbar, then Show log."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: 640, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

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

struct RevalidationBanner: View {
    let head: String
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
