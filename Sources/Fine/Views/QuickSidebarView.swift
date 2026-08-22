import SwiftUI

/// Fine의 열린 세션과 Claude transcript 최근 항목을 표시하는 최소 사이드바.
struct QuickSidebarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var recentScanner = QuickConversationScanner.shared
    @State private var isHoveringNew = false

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
                    LazyVStack(spacing: 3) {
                        ForEach(appState.sessions) { session in
                            QuickSessionRow(
                                session: session,
                                isSelected: appState.selectedSession?.id == session.id,
                                onSelect: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                        appState.selectSession(session)
                                    }
                                },
                                onClose: { appState.removeSession(session) }
                            )
                        }
                    }
                    .padding(.horizontal, FineTheme.sidebarInset)
                }
                .frame(maxHeight: 208)
            }

            QuickSectionHeader(title: "최근 항목") {
                Button {
                    recentScanner.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("최근 대화 새로고침")
            }

            Group {
                if recentScanner.conversations.isEmpty {
                    Text("최근 대화가 없습니다")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, FineTheme.sidebarInset)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(recentScanner.conversations) { conversation in
                                QuickRecentConversationRow(
                                    conversation: conversation,
                                    onResume: {
                                        appState.resumeConversation(conversation)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, FineTheme.sidebarInset)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
        .background { GlassSidebarBackground() }
        .onAppear {
            recentScanner.start()
            recentScanner.rescan()
        }
    }
}

private struct QuickSessionRow: View {
    @ObservedObject var session: TerminalSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: FineTheme.iconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: FineTheme.iconFrame)

            Text(session.name)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Circle()
                .fill(session.isRunning ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.35))
                .frame(width: 5, height: 5)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("대화 종료")
            .opacity(isHovering || isSelected ? 1 : 0)
        }
        .padding(.vertical, FineTheme.rowVerticalPadding)
        .padding(.horizontal, FineTheme.rowHorizontalPadding)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: FineTheme.rowCornerRadius, style: .continuous)
                    .fill(FineTheme.selectedFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: FineTheme.rowCornerRadius, style: .continuous)
                            .stroke(FineTheme.selectedRim, lineWidth: 1)
                    }
            } else if isHovering {
                RoundedRectangle(cornerRadius: FineTheme.rowCornerRadius, style: .continuous)
                    .fill(FineTheme.hoverFill)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

private struct QuickRecentConversationRow: View {
    let conversation: QuickConversation
    let onResume: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: FineTheme.iconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: FineTheme.iconFrame)

            Text(conversation.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(relativeTime(conversation.modifiedAt))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, FineTheme.rowVerticalPadding)
        .padding(.horizontal, FineTheme.rowHorizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: FineTheme.rowCornerRadius, style: .continuous)
                .fill(isHovering ? FineTheme.hoverFill : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                onResume()
            }
        }
        .help("이 대화 재개")
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
