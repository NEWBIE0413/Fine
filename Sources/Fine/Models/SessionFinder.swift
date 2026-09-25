import AppKit
import Foundation

/// 찾기 모드. "zeb 브라우저 만든 세션" 같은 말로 예전 대화를 찾아 연다.
///
/// Fine이 최근 대화 목록과 각 대화의 최근 요청 몇 줄을 모으고, Haiku는 그중 하나의
/// 번호만 고른다. 목록을 긁는 일까지 모델에게 도구로 시키면 턴이 늘어 수십 초가 되고,
/// Fine은 이미 그 목록을 들고 있다. 고른 대화가 열린 탭이면 그 탭으로 가고, 아니면 이어서 연다.
enum SessionFinder {
    struct Candidate: Equatable {
        let conversation: QuickConversation
        /// 최근 사용자 요청 몇 줄. 제목은 첫 요청에서 나와서, 대화가 흘러간 곳을 모른다.
        let recentPrompts: [String]
        let isOpen: Bool
    }

    enum Outcome: Equatable {
        case found(Candidate, reason: String)
        case notFound(reason: String)
        case failed(String)
    }

    /// 넓을수록 오래된 대화까지 닿지만, 첫 찾기에서 그만큼 transcript를 읽는다.
    /// (최근 80개 ≈ 130MB, 두 번째부터는 늘어난 부분만 읽는다.)
    static let candidateLimit = 80
    static let promptsPerCandidate = 3
    static let timeout: TimeInterval = 60

    // MARK: - 후보

    private static let queue = DispatchQueue(label: "Fine.SessionFinder", qos: .userInitiated)
    /// 찾기마다 transcript 전체를 다시 읽지 않도록, 화면 목록과 따로 색인을 들고 있는다.
    /// 화면 목록의 색인은 보이는 쪽만 남기므로 함께 쓰면 서로의 캐시를 지운다.
    nonisolated(unsafe) private static var index = TranscriptTitleIndex()

    /// 최근 대화 후보. 무거운 읽기는 백그라운드에서 하고, 결과는 메인 스레드로 돌려준다.
    static func gather(
        openSessionIDs: Set<String>,
        limit: Int = candidateLimit,
        directory: URL = QuickConversationScanner.defaultTranscriptsDirectory(),
        store: HarnessSessionStore? = .local,
        workingDirectory: String = QuickSessionPolicy.workingDirectory,
        completion: @escaping ([Candidate]) -> Void
    ) {
        queue.async {
            let claude = QuickConversationScanner.scanClaude(
                directory: directory, limit: limit, tracked: [], index: &index
            ).rows
            let others = store?.recentConversations(workingDirectory: workingDirectory, limit: limit) ?? []
            let conversations = QuickConversationScanner.merged(claude, others).prefix(limit)
            let candidates = conversations.map { conversation in
                Candidate(
                    conversation: conversation,
                    recentPrompts: conversation.transcriptURL.map { recentPrompts(in: $0) } ?? [],
                    isOpen: openSessionIDs.contains(conversation.id)
                )
            }
            DispatchQueue.main.async { completion(candidates) }
        }
    }

    /// transcript 끝부분에서 사용자 요청만 뽑는다. 전체를 읽으면 수십 MB라 꼬리만 본다.
    static func recentPrompts(in url: URL, count: Int = promptsPerCandidate, tailBytes: UInt64 = 196_608) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
        guard let data = try? handle.readToEnd() else { return [] }
        return HarnessTranscript.parseClaude(data)
            .filter { $0.role == "user" && !$0.text.hasPrefix("Caveat:") }
            .suffix(count)
            .map { oneLine($0.text, limit: 140) }
    }

    private static func oneLine(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    // MARK: - Haiku에게 묻기

    static let systemPrompt = """
        You pick the one conversation, from a numbered list, that the user is looking for. \
        Match on meaning, not only on shared words: titles come from the first request and \
        "recent" lines show where the conversation went later. If none fits, answer null \
        instead of forcing a guess. Write the reason in Korean, one short sentence.
        """

    static let schema = """
        {"type":"object","properties":{"pick":{"type":["integer","null"]},"reason":{"type":"string"}},"required":["pick","reason"]}
        """

    static func prompt(query: String, candidates: [Candidate], now: Date = Date()) -> String {
        let when = DateFormatter()
        when.locale = Locale(identifier: "ko_KR")
        when.dateFormat = "M월 d일 (E) HH:mm"
        var lines = [
            "Fine에서 최근에 연 대화 목록이다. 사용자가 찾는 대화 하나의 번호를 골라라.",
            "지금: \(when.string(from: now))",
            "",
            "찾는 것: \(query)",
            "",
        ]
        for (offset, candidate) in candidates.enumerated() {
            let conversation = candidate.conversation
            var head = "[\(offset + 1)] \(oneLine(conversation.title, limit: 120)) | \(conversation.harness.title)"
                + " | \(when.string(from: conversation.modifiedAt))"
            if candidate.isOpen { head += " | 열린 탭" }
            lines.append(head)
            if !candidate.recentPrompts.isEmpty {
                lines.append("    최근: " + candidate.recentPrompts.map { "\"\($0)\"" }.joined(separator: " / "))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 사용자의 Claude Code를 그대로 쓰되, 이 질문 하나에 필요 없는 것은 전부 끈다.
    /// 도구 없음, 설정·MCP·스킬 없음, 생각 없음, 기록 없음 — 찾기 질문이 최근 대화 목록에
    /// 새 대화로 끼어들면 안 된다.
    static func arguments() -> [String] {
        [
            "-p", "--model", "haiku",
            "--no-session-persistence",
            "--setting-sources", "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--system-prompt", systemPrompt,
            "--output-format", "json",
            "--json-schema", schema,
            // 가변 인자라 맨 끝에 둔다. 질문은 stdin으로 넣는다.
            "--tools", "",
        ]
    }

    static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var result = QuickSessionPolicy.applyingEnvironment(base, launch: .blank, configuration: .default)
        // 기록을 남기지 않는 한 번짜리 질문이다. 탭 세션용 강제 보존을 걷어낸다.
        result.removeValue(forKey: "CLAUDE_CODE_FORCE_SESSION_PERSISTENCE")
        // ccv 런처에게 주는 값이다. 순정 claude를 직접 부르므로 남길 이유가 없다.
        result.removeValue(forKey: "CCV_PROXY")
        result["MAX_THINKING_TOKENS"] = "0"
        return result
    }

    /// `claude -p`의 JSON 결과를 해석한다.
    static func parse(_ output: Data, candidates: [Candidate]) -> Outcome {
        guard let object = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            let text = String(decoding: output.prefix(300), as: UTF8.self)
            return .failed(text.isEmpty ? "Claude가 아무 답도 내지 않았습니다" : text)
        }
        if object["is_error"] as? Bool == true {
            return .failed((object["result"] as? String).map { oneLine($0, limit: 200) } ?? "Claude 호출이 실패했습니다")
        }
        guard let answer = object["structured_output"] as? [String: Any] else {
            return .failed("구조화된 답이 없습니다")
        }
        let reason = (answer["reason"] as? String).map { oneLine($0, limit: 200) } ?? ""
        guard let pick = (answer["pick"] as? NSNumber)?.intValue else {
            return .notFound(reason: reason)
        }
        guard candidates.indices.contains(pick - 1) else {
            return .notFound(reason: reason.isEmpty ? "목록에 없는 번호를 골랐습니다" : reason)
        }
        return .found(candidates[pick - 1], reason: reason)
    }

    /// Haiku를 한 번 부른다. 끝나면 메인 스레드에서 알린다.
    static func ask(
        query: String, candidates: [Candidate],
        executable: String = QuickSessionPolicy.claudeExecutablePath,
        completion: @escaping (Outcome) -> Void
    ) {
        guard !candidates.isEmpty else {
            completion(.notFound(reason: "찾아볼 최근 대화가 없습니다"))
            return
        }
        let input = prompt(query: query, candidates: candidates)
        queue.async {
            let outcome = run(executable: executable, input: input, candidates: candidates)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private static func run(executable: String, input: String, candidates: [Candidate]) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments()
        process.environment = environment()
        // 프로젝트 CLAUDE.md를 끌어오지 않도록 빈 곳에서 띄운다.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return .failed("claude를 실행하지 못했습니다: \(error.localizedDescription)")
        }
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()

        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { if process.isRunning { process.terminate() } }
        timer.resume()
        // 파이프가 차서 멈추지 않도록 끝날 때까지 읽는다.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()

        if process.terminationReason == .uncaughtSignal {
            return .failed("\(Int(timeout))초 안에 답이 오지 않았습니다")
        }
        let outcome = parse(output, candidates: candidates)
        if case .failed(let message) = outcome, !errors.isEmpty {
            return .failed(message + " — " + oneLine(String(decoding: errors.suffix(300), as: UTF8.self), limit: 200))
        }
        return outcome
    }
}

// MARK: - 열기

extension SessionFinder {
    /// 지금 어느 창에서든 탭으로 떠 있는 대화들.
    @MainActor
    static func openSessionIDs() -> Set<String> {
        Set(FineWindowRegistry.shared.liveEntries().flatMap { $0.state.sessions.compactMap(\.resumableSessionID) })
    }

    /// 이미 열린 탭이면 그 창·탭으로 가고, 아니면 `state`의 창에서 이어서 연다.
    /// 같은 대화를 두 탭에서 이어 쓰면 두 프로세스가 한 transcript에 번갈아 쓴다.
    @MainActor
    @discardableResult
    static func open(_ conversation: QuickConversation, from state: AppState) -> AppState {
        for entry in FineWindowRegistry.shared.liveEntries() {
            guard let session = entry.state.sessions.first(where: {
                $0.configuration.harness == conversation.harness && $0.matchesConversation(sessionId: conversation.id)
            }) else { continue }
            entry.state.selectSession(session)
            if entry.state !== state, let window = entry.window {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
            return entry.state
        }
        state.resumeConversation(conversation)
        return state
    }

    /// 모으고, 묻고, 연다. 화면(찾기 모드)과 CLI(`fine find`)가 같은 길을 쓴다.
    @MainActor
    static func find(
        _ query: String, from state: AppState, open shouldOpen: Bool = true,
        progress: ((Int) -> Void)? = nil,
        completion: @escaping (Outcome) -> Void
    ) {
        gather(openSessionIDs: openSessionIDs()) { candidates in
            progress?(candidates.count)
            ask(query: query, candidates: candidates) { outcome in
                if shouldOpen, case .found(let candidate, _) = outcome {
                    open(candidate.conversation, from: state)
                }
                completion(outcome)
            }
        }
    }
}
