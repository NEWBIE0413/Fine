import SwiftUI

/// Fine의 열린 세션과 세 하네스의 최근 대화를 표시하는 사이드바.
struct QuickSidebarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var recentScanner = QuickConversationScanner.shared
    @State private var isHoveringNew = false
    @AppStorage("recentConversationsExpanded") private var recentExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                appState.showHome()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: FineTheme.iconSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: FineTheme.iconFrame)
                    Text("새 대화")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, FineTheme.rowVerticalPadding)
                .padding(.horizontal, FineTheme.rowHorizontalPadding)
                .background(
                    RoundedRectangle(cornerRadius: FineTheme.rowCornerRadius, style: .continuous)
                        .fill(isHoveringNew ? FineTheme.hoverFill : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, FineTheme.sidebarInset)
            .padding(.top, FineTheme.titlebarClearance)
            .onHover { isHoveringNew = $0 }
            .animation(.easeOut(duration: 0.14), value: isHoveringNew)

            if !appState.sessions.isEmpty {
                QuickSectionHeader(title: "열린 대화") {
                    EmptyView()
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.sessions) { session in
                            QuickSessionRow(
                                session: session,
                                isSelected: appState.selectedSession?.id == session.id,
                                onSelect: { appState.selectSession(session) },
                                onClose: { appState.removeSession(session) },
                                drag: OpenSessionDrag(windowID: appState.windowStateID, sessionID: session.id),
                                onDropSession: { item, edge in
                                    guard item.windowID == appState.windowStateID else { return false }
                                    return appState.moveSession(id: item.sessionID, relativeTo: session.id, edge: edge)
                                }
                            )
                            .accessibilityAction(named: Text("위로 이동")) {
                                appState.moveSession(id: session.id, by: -1)
                            }
                            .accessibilityAction(named: Text("아래로 이동")) {
                                appState.moveSession(id: session.id, by: 1)
                            }
                        }
                    }
                    .background(alignment: .top) {
                        // One persistent selection block travels between rows; only this
                        // layer animates, so terminal selection and row hitboxes stay immediate.
                        let selectedIndex = appState.sessions.firstIndex { $0.id == appState.selectedSession?.id }
                        RoundedRectangle(cornerRadius: FineTheme.rowCornerRadius, style: .continuous)
                            .fill(FineTheme.selectedFill)
                            .overlay {
                                RoundedRectangle(cornerRadius: FineTheme.rowCornerRadius, style: .continuous)
                                    .stroke(FineTheme.selectedRim, lineWidth: 1)
                            }
                            .frame(height: 37)
                            .offset(y: CGFloat(selectedIndex ?? 0) * 37)
                            .opacity(selectedIndex == nil ? 0 : 1)
                            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: selectedIndex)
                            .allowsHitTesting(false)
                    }
                    .padding(.horizontal, FineTheme.sidebarInset)
                }
                .frame(height: min(208, CGFloat(appState.sessions.count) * 37))
            }

            ZStack(alignment: .bottom) {
                if recentExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        recentHeader
                        recentConversations
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                } else {
                    Button { recentExpanded = true } label: {
                        recentHandle
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("최근 항목 펼치기")
                    .help("최근 항목 펼치기")
                    .padding(.horizontal, FineTheme.sidebarInset)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .clipped()
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1), value: recentExpanded)
        }
        .frame(maxHeight: .infinity)
        .background { GlassSidebarBackground() }
        .onAppear {
            recentScanner.start()
        }
    }

    private var recentHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: 28, height: 2)
            .accessibilityHidden(true)
    }

    private var recentHeader: some View {
        QuickSectionHeader(title: "최근 항목") {
            Button {
                recentScanner.rescan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("최근 대화 새로고침")
        }
        .overlay {
            Button { recentExpanded = false } label: {
                recentHandle
                    .frame(width: 44, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("최근 항목 숨기기")
            .help("최근 항목 숨기기")
                // Match the section header's vertical content insets.
                .padding(.top, 18)
                .padding(.bottom, 5)
        }
    }

    private var recentConversations: some View {
        Group {
            if recentScanner.conversations.isEmpty {
                Text(recentScanner.isLoading ? "최근 대화를 불러오는 중…" : "최근 대화가 없습니다")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, FineTheme.sidebarInset)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(recentScanner.conversations, id: \.listID) { conversation in
                            QuickRecentConversationRow(
                                conversation: conversation,
                                onResume: {
                                    appState.resumeConversation(conversation)
                                }
                            )
                        }
                        if recentScanner.hasMore {
                            Button(recentScanner.isLoading ? "불러오는 중…" : "더 보기") { recentScanner.loadNextPage() }
                                .font(.system(size: 11))
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .disabled(recentScanner.isLoading)
                                .padding(.vertical, 12)
                                .onAppear { recentScanner.loadNextPage() }
                        }
                    }
                    .padding(.horizontal, FineTheme.sidebarInset)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct QuickSessionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: TerminalSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let drag: OpenSessionDrag
    let onDropSession: (OpenSessionDrag, SessionInsertionEdge) -> Bool
    @State private var insertionEdge: SessionInsertionEdge?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(session.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Circle()
                .fill(session.isRunning ? Color.green.opacity(0.72) : Color.secondary.opacity(0.3))
                .frame(width: 5, height: 5)
        }
        .padding(.leading, FineTheme.rowHorizontalPadding)
        .padding(.trailing, 36)
        .frame(maxWidth: .infinity)
        .frame(height: 37)
        .accessibilityHidden(true)
        .background {
            RoundedRectangle(cornerRadius: FineTheme.rowCornerRadius, style: .continuous)
                .fill(FineTheme.hoverFill)
                .opacity(isHovering && !isSelected ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
                .allowsHitTesting(false)
        }
        .overlay(alignment: insertionEdge == .before ? .top : .bottom) {
            if insertionEdge != nil {
                Capsule()
                    .fill(Color.primary.opacity(0.48))
                    .frame(height: 2)
                    .padding(.horizontal, 4)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            SessionRowInteraction(item: drag, title: "\(session.name), \(session.configuration.harness.title)",
                                  onSelect: onSelect, onDrop: onDropSession,
                                  onTarget: { insertionEdge = $0 })
        }
        .overlay(alignment: .trailing) {
            if isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("대화 종료")
                .padding(.trailing, 4)
            }
        }
        .onHover { isHovering = $0 }
    }
}

struct QuickRecentConversationRow: View {
    let conversation: QuickConversation
    let onResume: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 8) {
                Text(conversation.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(relativeTime(conversation.modifiedAt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()

                HarnessLogo(harness: conversation.harness)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, FineTheme.rowVerticalPadding)
            .padding(.horizontal, FineTheme.rowHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: FineTheme.rowCornerRadius, style: .continuous)
                    .fill(isHovering ? FineTheme.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(conversation.title), \(conversation.harness.title)")
        .onHover { isHovering = $0 }
        .help("\(conversation.harness.title)에서 재개 · \(conversation.title)")
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(-date.timeIntervalSinceNow))
        if seconds < 60 { return "방금" }
        if seconds < 3_600 { return "\(seconds / 60)분 전" }
        if seconds < 86_400 { return "\(seconds / 3_600)시간 전" }
        return "\(seconds / 86_400)일 전"
    }
}
