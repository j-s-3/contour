import SwiftUI

struct ContextualChatView: View {
    let store: GraphStore
    let graph: PRGraph

    @FocusState private var composerFocused: Bool

    private var conversations: ConversationStore { store.conversations }

    var body: some View {
        Group {
            if let conversation = conversations.active, let resolved = graph.resolve(conversation.subject) {
                thread(conversation, resolved)
                    .id(conversation.id)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
            } else {
                ContentUnavailableView {
                    Label("No conversation", systemImage: "bubble.left.and.text.bubble.right")
                } description: {
                    Text("Right-click anything in the review and choose Ask about this… (⌘⇧A).")
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: conversations.activeId)
        .onExitCommand { conversations.close() }
        .environment(\.openURL, OpenURLAction { url in handle(url) })
    }

    private func thread(_ conversation: Conversation, _ resolved: ResolvedSubject) -> some View {
        VStack(spacing: 0) {
            header(resolved)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        contextCard(conversation, resolved)
                        if conversation.messages.isEmpty {
                            suggestions(conversation, resolved)
                        }
                        ForEach(conversation.messages) { message in
                            messageView(message, conversation: conversation).id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: conversation.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: conversation.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Divider()
            composer(conversation, resolved)
        }
        .onAppear { focusComposerSoon() }
        .onChange(of: conversations.focusRequest) { _, _ in focusComposerSoon() }
    }

    private func focusComposerSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { composerFocused = true }
    }

    private func header(_ resolved: ResolvedSubject) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: resolved.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(resolved.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(verbatim: "\(graph.pr.repo) #\(graph.pr.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            conversationsMenu
            Button {
                conversations.close()
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Close (esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    var conversationMenuContent: some View {
        Section("Conversations") {
            ForEach(conversations.conversations) { c in
                Button {
                    conversations.activeId = c.id
                } label: {
                    let title = ChatViewLogic.menuTitle(for: c, in: graph)
                    if c.id == conversations.activeId {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        }
        if let active = conversations.active {
            Divider()
            Button("Close This Conversation", role: .destructive) { conversations.remove(active) }
        }
    }

    private var conversationsMenu: some View {
        Menu {
            conversationMenuContent
        } label: {
            Image(systemName: "bubble.left.and.bubble.right")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(conversations.conversations.count > 1 ? .visible : .hidden)
        .fixedSize()
        .help("Conversations in this review")
    }

    private func contextCard(_ conversation: Conversation, _ resolved: ResolvedSubject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YOU ARE DISCUSSING")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                if let target = resolved.detailTarget {
                    Button("Open") { store.navigate(to: target) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(ChatViewLogic.summaryLines(for: resolved)) { line in
                    Text(line.text)
                        .font(line.isLead ? .callout.weight(.semibold) : .caption)
                        .foregroundStyle(line.isLead ? .primary : .secondary)
                        .lineLimit(line.isLead ? 2 : 1)
                        .truncationMode(.tail)
                }
            }
            let expansions = ChatContextBuilder.availableExpansions(for: resolved)
            if ChatViewLogic.showsContextChips(expansions: expansions, pinnedRefs: conversation.pinnedRefs) {
                FlowLayout(spacing: 6) {
                    ForEach(conversation.pinnedRefs) { ref in
                        chip("\(ref.display)", symbol: "pin.fill", on: true) {
                            ChatViewLogic.unpin(ref, in: conversation)
                        }
                        .help("Included in this conversation — click to remove")
                    }
                    ForEach(expansions) { expansion in
                        let on = conversation.expansions.contains(expansion)
                        chip(expansion.label, symbol: ChatViewLogic.expansionSymbol(on: on), on: on) {
                            ChatViewLogic.toggle(expansion, in: conversation)
                        }
                        .help(ChatViewLogic.expansionHelp(expansion, on: on))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.18)))
    }

    private func chip(_ text: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                Text(text).font(.caption2.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(on ? Color.accentColor : .secondary)
            .background(on ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func suggestions(_ conversation: Conversation, _ resolved: ResolvedSubject) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Ask about \(ChatViewLogic.subjectPhrase(for: resolved))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.bottom, 4)
            ForEach(ChatContextBuilder.suggestions(for: resolved), id: \.self) { suggestion in
                Button {
                    store.send(suggestion, in: conversation)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary)
                        Text(suggestion).font(.callout)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage, conversation: Conversation) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if !message.text.isEmpty {
                    ChatMarkdownView(text: message.text, linkify: linkify)
                }
                if message.isStreaming {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(ChatViewLogic.activityText(conversation.activity))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if let error = message.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func composer(_ conversation: Conversation, _ resolved: ResolvedSubject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let ref = ChatViewLogic.evidenceToOffer(
                current: store.current, pinnedRefs: conversation.pinnedRefs, subject: conversation.subject)
            {
                Button {
                    conversations.pin(ref, in: conversation)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("Include the code you're viewing:")
                        Text(ref.display).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(
                            .middle)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    "Ask about \(ChatViewLogic.subjectPhrase(for: resolved))…",
                    text: Binding(get: { conversation.draft }, set: { conversation.draft = $0 }),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...6)
                .focused($composerFocused)
                .onSubmit { store.send(conversation.draft, in: conversation) }
                if conversation.isResponding {
                    Button {
                        conversations.cancel(conversation)
                    } label: {
                        Image(systemName: "stop.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Stop")
                } else {
                    Button {
                        store.send(conversation.draft, in: conversation)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChatViewLogic.canSend(conversation.draft) ? Color.accentColor : Color.secondary)
                    .disabled(!ChatViewLogic.canSend(conversation.draft))
                    .help("Send (↩)")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator))
        }
        .padding(12)
    }

    private func linkify(_ text: String) -> String {
        ChatLinks.linkify(text, resolve: resolvePath, title: graph.linkTitle)
    }

    private func resolvePath(_ path: String) -> String? {
        ChatViewLogic.resolvePath(path, checkoutRoot: store.checkout?.rootDir, citedPaths: graph.citedPaths)
    }

    func handle(_ url: URL) -> OpenURLAction.Result {
        ChatViewLogic.handle(url, store: store, graph: graph) == .handled ? .handled : .systemAction
    }
}
