import SwiftUI

struct StartSourceList: View {
    let model: StartScreenModel
    let actions: StartScreenActions
    var onOpen: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                switch model.selection {
                case .reviewRequests: reviewRequests
                case .recents: recents
                case .watched(let id):
                    WatchedPullRequestsList(
                        repository: id, state: model.state(for: id), isFetching: model.isFetching(id),
                        labels: { model.labels(for: $0, in: id) },
                        failureMessage: { model.failureMessage(for: $0, repository: id) },
                        onRefresh: actions.refresh(id), onOpen: onOpen
                    )
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
