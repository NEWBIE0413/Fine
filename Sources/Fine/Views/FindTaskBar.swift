import SwiftUI

/// 찾기 모드에서 한 번의 찾기가 어디까지 왔는지.
enum QuickFindStatus: Equatable {
    case idle
    /// 최근 대화의 내용을 읽는 중. `since`는 찾기를 시작한 때다.
    case gathering(query: String, since: Date)
    /// Haiku가 고르는 중. 얼마나 남았는지는 알 수 없다 — `claude -p`는 진행을 알려 주지 않는다.
    case asking(query: String, count: Int, since: Date)
    /// 찾았고, 막대를 거둔 뒤 열 참이다.
    case found(title: String, wasOpen: Bool)
    case notFound(query: String, reason: String)
    case failed(query: String, message: String)

    /// 새 찾기를 받지 않는 동안. 찾은 뒤 여는 사이도 포함한다.
    var isBusy: Bool {
        switch self {
        case .gathering, .asking, .found: true
        case .idle, .notFound, .failed: false
        }
    }

    /// 결과만 남은 상태. 잠시 보여 주고 저절로 접힌다.
    var isSettled: Bool {
        switch self {
        case .notFound, .failed: true
        default: false
        }
    }

    var since: Date? {
        switch self {
        case .gathering(_, let since), .asking(_, _, let since): since
        default: nil
        }
    }
}

/// 입력창 아래에서 안내 문구 자리를 잠시 빌려 쓰는 작업 막대.
///
/// 진행은 아래 막대 하나가 맡는다. 막대는 차오르지 않고 흐르기만 한다 — Haiku가 답하기까지
/// 얼마나 남았는지는 알 수 없으므로, 채워 보이면 지어낸 숫자가 된다. 사실인 것만 적는다:
/// 지금 무엇을 하는지, 그리고 시작한 지 몇 초 지났는지.
struct FindTaskBar: View {
    let status: QuickFindStatus
    var onDismiss: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 흐르는 빛이 막대를 한 번 가로지르는 시간.
    static let sweep: TimeInterval = 1.3

    var body: some View {
        let palette = FinePalette.resolve(colorScheme)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: status.since == nil)) { timeline in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if let icon {
                        icon.frame(width: 16, height: 16)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .fineTracking(12.5)
                            .foregroundStyle(palette.isDark ? palette.ink : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(detail)
                            .font(.system(size: 11))
                            .fineTracking(11)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if let since = status.since {
                        Text(String(format: "%.1f초", max(0, timeline.date.timeIntervalSince(since))))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if status.isSettled {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.finePress)
                        .accessibilityLabel("닫기")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                track(at: timeline.date)
            }
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.isDark ? palette.glassFill : Color.white.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.isDark ? palette.glassEdgeTop.opacity(0.5) : FineTheme.divider, lineWidth: 1)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }

    /// 결과가 나온 뒤에만 아이콘을 둔다. 일하는 동안의 표시는 막대가 맡는다.
    private var icon: AnyView? {
        switch status {
        case .found:
            AnyView(Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(FineTheme.findAccent))
        case .notFound:
            AnyView(Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary))
        case .failed:
            AnyView(Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange))
        case .idle, .gathering, .asking:
            nil
        }
    }

    private var title: String {
        switch status {
        case .idle: ""
        case .gathering(let query, _), .asking(let query, _, _): "‘\(query)’ 찾는 중"
        case .found(let title, _): "찾았습니다 · \(title)"
        case .notFound(let query, _): "‘\(query)’에 맞는 대화를 찾지 못했습니다"
        case .failed: "찾지 못했습니다"
        }
    }

    private var detail: String {
        switch status {
        case .idle: ""
        case .gathering: "최근 대화의 내용을 읽는 중"
        case .asking(_, let count, _): "Haiku가 대화 \(count)개의 내용을 훑는 중"
        case .found(_, let wasOpen): wasOpen ? "열려 있는 탭으로 갑니다" : "이어서 엽니다"
        case .notFound(_, let reason): reason.isEmpty ? "설명을 바꿔 다시 찾아보세요" : reason
        case .failed(_, let message): message
        }
    }

    /// 일하는 동안은 빛 한 줄기가 왼쪽에서 오른쪽으로 흐른다. 찾으면 한 번 가득 찬다.
    /// 결과만 남으면 막대는 사라진다 — 더 기다릴 것이 없다.
    private func track(at date: Date) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            switch status {
            case .gathering, .asking:
                let segment = width * 0.32
                let phase = reduceMotion ? 0.5
                    : date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.sweep) / Self.sweep
                LinearGradient(
                    colors: [FineTheme.findAccent.opacity(0), FineTheme.findAccent, FineTheme.findAccent.opacity(0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: segment)
                .offset(x: -segment + CGFloat(phase) * (width + segment))
            case .found:
                FineTheme.findAccent
            case .idle, .notFound, .failed:
                Color.clear
            }
        }
        .frame(height: 2)
        .background(status.isSettled ? Color.clear : FineTheme.divider)
        .clipped()
    }
}
