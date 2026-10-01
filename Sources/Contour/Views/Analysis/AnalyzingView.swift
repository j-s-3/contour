import SwiftUI

struct AnalyzingView: View {
    let stage: PipelineStage
    let log: [PipelineProgressEntry]
    var markNamespace: Namespace.ID

    @AppStorage("showsAnalysisActivity") private var showsActivity = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                AnalyzingMark(stage: stage)
                    .matchesContourMark(in: markNamespace)
                    .frame(height: ContourMarkView.heroHeight)
                Text(Self.headline(stage))
                    .font(.title3)
                    .padding(.top, 28)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: Self.headline(stage))
                Text(latestDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
                    .padding(.top, 6)
                Spacer()
                if !showsActivity { Spacer().frame(height: 60) }
                activityToggle
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsActivity {
                Divider()
                console
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    nonisolated static func headline(_ stage: PipelineStage) -> String {
        switch stage {
        case .fetching, .checkingOut, .cacheCheck: return "Opening the pull request…"
        case .ticket, .behaviorChange, .understanding: return "Understanding the change…"
        case .architecture: return "Analyzing architecture…"
        case .decisions: return "Finding the decisions it makes…"
        case .flows: return "Tracing the flows it touches…"
        case .judgment: return "Deciding what needs your judgment…"
        }
    }

    private var latestDetail: String { Self.latestDetail(log: log, stage: stage) }

    nonisolated static func latestDetail(log: [PipelineProgressEntry], stage: PipelineStage) -> String {
        guard let last = log.last else { return stage.rawValue }
        return last.detail.isEmpty ? last.stage : "\(last.stage) — \(last.detail)"
    }

    private var activityToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showsActivity.toggle() }
        } label: {
            Label(
                showsActivity ? "Hide activity" : "Show activity",
                systemImage: showsActivity ? "chevron.down" : "chevron.up"
            )
            .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Every step the harness takes as it reads the repository")
    }

    private var console: some View { AnalysisConsoleView(log: log) }
}

struct AnalysisConsoleView: View {
    let log: [PipelineProgressEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(log) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.stage)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 160, alignment: .leading)
                                .lineLimit(1)
                            Text(entry.detail)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(entry.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear { if let last = log.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            .onChange(of: log.count) { _, _ in
                if let last = log.last {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}
