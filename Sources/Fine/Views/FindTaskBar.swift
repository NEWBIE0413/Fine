import SwiftUI

/// 찾기 모드에서 한 번의 찾기가 어디까지 왔는지.
enum QuickFindStatus: Equatable {
    case idle
    case gathering(query: String, since: Date)
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
}

/// 입력창 아래에서 안내 문구 자리를 잠시 빌려 쓰는 작업 막대.
///
/// 몇 초 걸리는 일을 글자 한 줄로만 알리면 멈춘 것처럼 보인다. 지금 어느 단계인지,
/// 얼마나 지났는지, 앞으로 가고 있는지를 한 막대에 모은다.
struct FindTaskBar: View {
    let status: QuickFindStatus
    var onDismiss: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Haiku가 보통 이 정도 걸린다(실측 4~5초). 막대가 이 시간 동안 대부분을 채우고,
    /// 더 걸리면 끝에 가까이서 천천히 기어간다 — 멈추지도, 다 찼다고 거짓말하지도 않는다.
    static let expectedAnswer: TimeInterval = 4.5

    var body: some View {
        let palette = FinePalette.resolve(colorScheme)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !status.isBusy || reduceMotion)) { timeline in
            let elapsed = since.map { timeline.date.timeIntervalSince($0) } ?? 0
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    icon
                        .frame(width: 16, height: 16)
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
                    if status.isBusy, since != nil {
                        Text(String(format: "%.1f초", elapsed))
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

                track(progress: progress(elapsed: elapsed))
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

    private var since: Date? {
        switch status {
        case .gathering(_, let since), .asking(_, _, let since): since
        default: nil
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .gathering, .asking, .idle:
            ProgressView().controlSize(.small).scaleEffect(0.8)
        case .found:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(FineTheme.findAccent)
        case .notFound:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch status {
        case .idle: ""
        case .gathering(let query, _), .asking(let query, _, _): "‘\(query)’ 찾는 중"
        case .found(let title, _): "찾았습니다 · \(title)"
        case .notFound: "맞는 대화를 찾지 못했습니다"
        case .failed: "찾지 못했습니다"
        }
    }

    private var detail: String {
        switch status {
        case .idle: ""
        case .gathering: "최근 대화를 모으는 중"
        case .asking(_, let count, _): "Haiku가 최근 대화 \(count)개를 훑는 중"
        case .found(_, let wasOpen): wasOpen ? "열려 있는 탭으로 갑니다" : "이어서 엽니다"
        case .notFound(_, let reason): reason.isEmpty ? "설명을 바꿔 다시 찾아보세요" : reason
        case .failed(_, let message): message
        }
    }

    /// 단계마다 막대가 차는 몫. 모으기는 짧고, 고르기가 대부분이다.
    private func progress(elapsed: TimeInterval) -> Double {
        switch status {
        case .idle, .notFound, .failed: 0
        case .gathering: 0.08 + 0.07 * min(1, elapsed / 0.6)
        // 고르기는 모으기가 끝난 뒤 시작했지만, 막대는 전체 경과로 흘러도 충분하다.
        case .asking: 0.15 + 0.8 * (1 - exp(-elapsed / (Self.expectedAnswer / 2.2)))
        case .found: 1
        }
    }

    private func track(progress: Double) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(FineTheme.findAccent.opacity(status.isSettled ? 0 : 0.85))
                .frame(width: geometry.size.width * progress)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: status == .idle)
        }
        .frame(height: 2)
        .background(FineTheme.divider)
        .opacity(status.isSettled ? 0 : 1)
    }
}
