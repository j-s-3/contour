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
