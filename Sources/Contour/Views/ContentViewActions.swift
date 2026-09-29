import SwiftUI

@MainActor
struct ContentViewActions {
    let store: GraphStore

    func load(_ url: String) { store.load(prURL: url) }
    func goBack() { store.goBack() }
    func goForward() { store.goForward() }
    func close() { store.close() }
    func reopen() { store.reopen() }
    func copyReviewSummary() { store.copyReviewSummary() }
    func openOnGitHub() { store.openOnGitHub() }
    func stopAnalysis() { store.stopAnalysis() }
    func retry(_ stage: PipelineStage) { store.retry(stage) }
    func navigate(_ target: NavigationTarget) { store.navigate(to: target) }
    func openEvidence(_ ref: CodeRef) { store.navigate(to: .evidence(ref)) }
    func approve() { store.submitReview(.approve) }
    func requestChanges(_ comment: String) { store.submitReview(.requestChanges, comment: comment) }
    func acknowledge() {}

    func openOnGitHub(_ session: PRSessionActions) -> () -> Void {
        { session.openOnGitHub() }
    }

    func copyLink(_ session: PRSessionActions) -> () -> Void {
        { session.copyLink() }
    }

    func toggleConversations() {
        withAnimation(ContentView.spring) { store.toggleConversations() }
    }

    func setReviewerState(_ id: String, _ state: ReviewerState) {
        store.setReviewerState(state, forDecision: id)
    }

    func setReviewerNote(_ id: String, _ note: String) {
        store.setReviewerNote(note, forDecision: id)
    }

    func setToReview(_ id: String, _ toReview: Bool) {
        store.setToReview(toReview, forDecision: id)
    }

    func retryAction(_ stage: PipelineStage) -> () -> Void {
        { store.retry(stage) }
    }

    func navigateAction(_ target: NavigationTarget) -> () -> Void {
        { store.navigate(to: target) }
    }

    func askAction(_ question: String) -> () -> Void {
        { withAnimation(ContentView.spring) { store.ask(question, about: .pullRequest) } }
    }

    func turnOn(_ flag: Binding<Bool>) -> () -> Void {
        { flag.wrappedValue = true }
    }

    func openDifferent(focusRequest: Binding<Int>) -> () -> Void {
        {
            store.close()
            focusRequest.wrappedValue += 1
        }
    }

    func finishOnboarding(_ needsOnboarding: Binding<Bool>) -> (String?) -> Void {
        { firstURL in
            needsOnboarding.wrappedValue = false
            ContentView.openFirstPR(firstURL, load: load)
        }
    }

    func openLink(needsOnboarding: Bool) -> (URL) -> Void {
        { url in ContentView.openLink(url, needsOnboarding: needsOnboarding, load: load) }
    }

    func requestChangesSheet(for graph: PRGraph) -> () -> RequestChangesSheet {
        {
            RequestChangesSheet(
                title: "Request changes on \(graph.pr.repo) #\(graph.pr.number)", onSubmit: requestChanges)
        }
    }

    func conversationsPresented() -> Binding<Bool> {
        Binding(
            get: { store.conversations.isPresented },
            set: { store.conversations.isPresented = $0 }
        )
    }

    func reviewFailurePresented() -> Binding<Bool> {
        Binding(
            get: { if case .failed = store.review { true } else { false } },
            set: { if !$0 { store.dismissReviewFailure() } }
        )
    }
}
