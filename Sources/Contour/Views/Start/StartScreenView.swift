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

    static func loadPastedText(from providers: [NSItemProvider], apply: @escaping @MainActor (String) -> Void) {
        guard let provider = providers.first else { return }
        Task { @MainActor in
            guard
                let text = await withCheckedContinuation({ continuation in
                    _ = provider.loadObject(ofClass: String.self) { text, _ in
                        continuation.resume(returning: text)
                    }
                })
            else { return }
            apply(StartScreenLogic.resolvedPasteText(text))
        }
    }

    private func submit() {
        guard GitHubService.normalize(urlText) != nil else { return }
        onSubmit(urlText)
    }

    private func clipboardOfferRow(_ offer: ClipboardOffer) -> some View {
        ClipboardOfferRow(
            offer: offer, onOpen: onSubmit, onOpenUnread: openUnreadClipboard,
            onDismiss: {
                declinedChangeCount = pasteboard.changeCount
                clipboardOffer = nil
            }
        )
    }

    private func checkClipboard() async {
        let changeCount = pasteboard.changeCount
        guard !StartScreenLogic.isDeclined(changeCount: changeCount, declinedChangeCount: declinedChangeCount) else {
            clipboardOffer = nil
            return
        }
        if #available(macOS 15.4, *), pasteboard.accessBehavior != .alwaysAllow {
            let patterns =
                pasteboard.accessBehavior == .alwaysDeny
                ? []
                : (try? await pasteboard.detectedPatterns(for: [\.probableWebURL])) ?? []
            clipboardOffer = StartScreenLogic.offer(
                detectedProbableWebURL: patterns.contains(\.probableWebURL), changeCount: changeCount
            )
            return
        }
        clipboardOffer = StartScreenLogic.offer(fromReadableClipboardText: pasteboard.string(forType: .string))
    }

    private func openUnreadClipboard(_ changeCount: Int) {
        clipboardOffer = nil
        declinedChangeCount = changeCount
        StartScreenLogic.perform(
            StartScreenLogic.resolveClipboardRead(pasteboard.string(forType: .string)),
            open: onSubmit, fillField: { urlText = $0 }
        )
    }
}
