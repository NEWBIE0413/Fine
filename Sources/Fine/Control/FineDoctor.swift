import AppKit
import Foundation

/// Fine이 자기 상태를 스스로 설명한다.
///
/// 보통 앱이라면 설정창과 로그인 화면이 있을 자리다. Fine은 그것을 두지 않는다 —
/// 인증은 이미 하네스들이 각자 들고 있고(claude, codex와 라우터, omp의 agent.db),
/// Fine이 그 위에 또 하나의 로그인을 만들면 토큰 체인만 하나 더 늘어난다.
///
/// 대신 이 명령이 무엇이 준비됐고 무엇이 빠졌는지, 그리고 **빠진 것을 어떤 명령으로
/// 채우는지**를 함께 내놓는다. 사람이 읽어도 되고, 에이전트가 그대로 실행해도 된다.
/// 상태만 알려주고 고치는 법을 숨기면 결국 사람이 문서를 뒤져야 한다.
enum FineDoctor {
    struct Check {
        let name: String
        let ok: Bool
        let detail: String
        /// 문제가 있을 때 그대로 실행하면 되는 명령. 없으면 nil.
        var fix: String?
        /// 없어도 앱은 돈다 — 기능 하나가 빠질 뿐이라는 표시.
        var optional = false

        var json: [String: Any] {
            var row: [String: Any] = ["name": name, "ok": ok, "detail": detail, "optional": optional]
            if let fix { row["fix"] = fix }
            return row
        }
    }

    @MainActor
    static func run() -> [String: Any] {
        var checks: [Check] = []
        checks.append(contentsOf: harnessChecks())
        checks.append(contentsOf: serviceChecks())
        checks.append(contentsOf: preferenceChecks())

        let blocking = checks.filter { !$0.ok && !$0.optional }
        return [
            "ok": blocking.isEmpty,
            "checks": checks.map(\.json),
            "summary": blocking.isEmpty
                ? "쓸 준비가 됐습니다"
                : "\(blocking.count)개를 채워야 합니다",
        ]
    }

    // MARK: - 하네스

    @MainActor
    private static func harnessChecks() -> [Check] {
        QuickHarness.allCases.map { harness in
            let path = executablePath(for: harness)
            let exists = FileManager.default.isExecutableFile(atPath: path)
            return Check(
                name: "\(harness.title) 실행 파일",
                ok: exists,
                detail: exists ? path : "\(path) 없음",
                fix: exists ? nil : installHint(for: harness),
                // 하나만 있어도 Fine은 쓸 수 있다. 전부 갖출 이유는 없다.
                optional: harness != .claude
            )
        }
    }

    private static func executablePath(for harness: QuickHarness) -> String {
        switch harness {
        case .claude: QuickSessionPolicy.ccvExecutablePath
        case .codex: QuickSessionPolicy.codexExecutablePath
        case .opencode: QuickSessionPolicy.opencodeExecutablePath
        case .omp: QuickSessionPolicy.ompExecutablePath
        }
    }

    private static func installHint(for harness: QuickHarness) -> String {
        switch harness {
        case .claude: "ccv 런처를 ~/myworld/ccv 에 두세요"
        case .codex: "brew install codex"
        case .opencode: "curl -fsSL https://opencode.ai/install | bash"
        case .omp: "bun add -g @oh-my-pi/pi-coding-agent"
        }
    }

    // MARK: - 곁들이는 서비스

    private static func serviceChecks() -> [Check] {
        [
            Check(
                name: "모델 라우터",
                ok: reachable(port: 4141),
                detail: reachable(port: 4141)
                    ? "127.0.0.1:4141 응답함 — Claude 외 제공사도 고를 수 있습니다"
                    : "127.0.0.1:4141 응답 없음 — Claude 모델만 보입니다",
                fix: reachable(port: 4141) ? nil : "라우터를 실행하세요 (없으면 Claude 모델만 씁니다)",
                optional: true
            ),
            Check(
                name: "kev 판정 서버",
                ok: reachable(port: 8009),
                detail: reachable(port: 8009)
                    ? "127.0.0.1:8009 응답함 — 자동 모드와 인사말이 동작합니다"
                    : "127.0.0.1:8009 응답 없음 — 자동 모드는 폴백으로 시작합니다",
                fix: reachable(port: 8009) ? nil : "~/cld/jev/kev-serve.sh",
                optional: true
            ),
        ]
    }

    /// 로컬 포트가 살아 있는지만 본다. HTTP까지 갈 필요가 없고, 오래 기다릴 이유도 없다.
    private static func reachable(port: UInt16, timeout: TimeInterval = 0.25) -> Bool {
        let socketHandle = socket(AF_INET, SOCK_STREAM, 0)
        guard socketHandle >= 0 else { return false }
        defer { close(socketHandle) }
        var timeoutValue = timeval(
            tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
        )
        setsockopt(socketHandle, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketHandle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    // MARK: - 설정

    @MainActor
    private static func preferenceChecks() -> [Check] {
        let configuration = QuickComposerPreferences.load()
        let scene = NightSceneView.userSceneURL
        return [
            Check(
                name: "기본 대화 설정",
                ok: true,
                detail: "\(configuration.harness.title) · "
                    + (configuration.isDefaultModel ? "기본 모델" : configuration.modelID)
                    + " · \(configuration.effort.rawValue)",
                fix: nil
            ),
            Check(
                name: "외형",
                ok: true,
                detail: FineAppearance.stored.title,
                fix: "fine appearance [system|light|dark]"
            ),
            Check(
                name: "홈 배경",
                ok: true,
                detail: scene.map { $0.lastPathComponent } ?? "기본 장면 (절차적 밤하늘)",
                fix: scene == nil ? "⇧⌘B 또는 ~/.fine/home-scene.png 에 파일을 두세요" : nil,
                optional: true
            ),
        ]
    }
}
