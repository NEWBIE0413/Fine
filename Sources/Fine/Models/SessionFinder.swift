import AppKit
import Foundation

/// 찾기 모드. "zeb 브라우저 만든 세션" 같은 말로 예전 대화를 찾아 연다.
///
/// Fine이 최근 대화들의 내용을 훑어 한 대화당 한 단락으로 줄이고, Haiku는 그 목록에서
/// 번호 하나만 고른다. 제목만 보여 주면 놓친다 — 제목은 첫 요청에서 나오고, 대화는 거기서
/// 한참 흘러간다. 그래서 요청을 처음부터 끝까지 고르게 뽑고, 찾는 말이 본문 어디에 나왔는지도
/// 함께 넘긴다. 목록을 긁는 일까지 모델에게 도구로 시키면 턴이 늘어 수십 초가 된다.
/// 고른 대화가 열린 탭이면 그 탭으로 가고, 아니면 이어서 연다.
enum SessionFinder {
    struct Candidate: Equatable {
        let conversation: QuickConversation
        /// 대화 전체에서 고르게 뽑은 사용자 요청.
        let prompts: [String]
        /// 찾는 말이 본문(요청과 답 — 도구 출력은 뺀다)에 나온 자리.
        let passages: [String]
        let isOpen: Bool

        init(conversation: QuickConversation, prompts: [String] = [], passages: [String] = [], isOpen: Bool = false) {
            self.conversation = conversation
            self.prompts = prompts
            self.passages = passages
            self.isOpen = isOpen
        }
    }

    enum Outcome: Equatable {
        case found(Candidate, reason: String)
        case notFound(reason: String)
        case failed(String)
    }

    /// 넓을수록 오래된 대화까지 닿지만, 첫 찾기에서 그만큼 transcript를 읽는다.
    /// (최근 80개 ≈ 150MB. 한 번 읽은 대화는 크기·시각이 그대로면 다시 읽지 않는다.)
    static let candidateLimit = 80
    /// 한 대화에서 Haiku에게 보여 줄 요청 수와 본문 조각 수. 80개 × 이만큼 ≈ 3만 토큰.
    static let promptsPerCandidate = 8
    static let passagesPerCandidate = 3
    static let timeout: TimeInterval = 90

    // MARK: - 대화 내용

    /// 한 대화를 찾기에 쓸 만큼만 줄인 것. transcript를 다시 읽지 않으려고 들고 있는다.
    struct Digest: Equatable {
        /// 사용자 요청 전부, 한 줄로 잘라서. 순서대로.
        var prompts: [String] = []
        /// 요청과 답의 본문을 소문자 UTF-8로 이은 것. 찾는 말의 자리를 여기서 바이트로 찾는다 —
        /// 수 MB짜리 String에서 인덱스를 세면 글자 하나하나를 걸어가야 한다.
        var corpus = Data()
    }

    private struct Stamp: Equatable {
        let size: UInt64
        let modified: Date
    }

    private static let queue = DispatchQueue(label: "Fine.SessionFinder", qos: .userInitiated)
    /// 찾기마다 transcript 전체를 다시 읽지 않도록, 화면 목록과 따로 색인을 들고 있는다.
    /// 화면 목록의 색인은 보이는 쪽만 남기므로 함께 쓰면 서로의 캐시를 지운다.
    nonisolated(unsafe) private static var index = TranscriptTitleIndex()
    nonisolated(unsafe) private static var digests: [String: (stamp: Stamp, digest: Digest)] = [:]

    /// 최근 대화 후보. 무거운 읽기는 백그라운드에서 하고, 진행과 결과는 메인 스레드로 알린다.
    /// - Parameter progress: 읽은 대화 수 / 전체 (0…1).
    static func gather(
        query: String,
        openSessionIDs: Set<String>,
        limit: Int = candidateLimit,
        directory: URL = QuickConversationScanner.defaultTranscriptsDirectory(),
        store: HarnessSessionStore? = .local,
        workingDirectory: String = QuickSessionPolicy.workingDirectory,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping ([Candidate]) -> Void
    ) {
        queue.async {
            let claude = QuickConversationScanner.scanClaude(
                directory: directory, limit: limit, tracked: [], index: &index
            ).rows
            let others = store?.recentConversations(workingDirectory: workingDirectory, limit: limit) ?? []
            let conversations = Array(QuickConversationScanner.merged(claude, others).prefix(limit))
            let terms = keywords(in: query)
            var candidates: [Candidate] = []
            var reported = -1
            for (offset, conversation) in conversations.enumerated() {
                let digest = cachedDigest(for: conversation, store: store)
                candidates.append(Candidate(
                    conversation: conversation,
                    prompts: sample(digest.prompts, terms: terms, count: promptsPerCandidate),
                    passages: passages(in: digest.corpus, terms: terms, limit: passagesPerCandidate),
                    isOpen: openSessionIDs.contains(conversation.id)
                ))
                // 퍼센트가 한 칸씩 오를 때만 알린다. 대화마다 메인 스레드를 깨울 이유는 없다.
                let percent = (offset + 1) * 100 / max(1, conversations.count)
                if percent != reported, let progress {
                    reported = percent
                    DispatchQueue.main.async { progress(Double(percent) / 100) }
                }
            }
            if digests.count > limit * 3 {
                let keep = Set(conversations.map(\.listID))
                digests = digests.filter { keep.contains($0.key) }
            }
            DispatchQueue.main.async { completion(candidates) }
        }
    }

    private static func cachedDigest(for conversation: QuickConversation, store: HarnessSessionStore?) -> Digest {
        let key = conversation.listID
        if let url = conversation.transcriptURL {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.uint64Value,
                  let modified = attributes[.modificationDate] as? Date else { return Digest() }
            let stamp = Stamp(size: size, modified: modified)
            if let cached = digests[key], cached.stamp == stamp { return cached.digest }
            let digest = digest(claudeTranscript: url)
            digests[key] = (stamp, digest)
            return digest
        }
        // Codex·omp·OpenCode는 파일 경로 대신 하네스 저장소에서 읽는다. 수정 시각이 곧 도장이다.
        let stamp = Stamp(size: 0, modified: conversation.modifiedAt)
        if let cached = digests[key], cached.stamp == stamp { return cached.digest }
        let messages = HarnessTranscript.messages(
            harness: conversation.harness, sessionID: conversation.id, limit: 500,
            store: store ?? .local
        ) ?? []
        let digest = digest(messages)
        digests[key] = (stamp, digest)
        return digest
    }

    /// 도구 출력이 든 거대한 줄(수 MB)은 대화가 아니다. 파싱하기 전에 거른다.
    private static let maximumLineBytes = 262_144
    private static let userMarker = Data("\"type\":\"user\"".utf8)
    private static let assistantMarker = Data("\"type\":\"assistant\"".utf8)

    static func digest(claudeTranscript url: URL) -> Digest {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return Digest() }
        var kept = Data()
        for line in data.split(separator: 10, omittingEmptySubsequences: true)
        where line.count <= maximumLineBytes
            && (line.range(of: userMarker) != nil || line.range(of: assistantMarker) != nil) {
            kept.append(line)
            kept.append(10)
        }
        return digest(HarnessTranscript.parseClaude(kept))
    }

    static func digest(_ messages: [HarnessTranscript.Message]) -> Digest {
        var result = Digest()
        for message in messages {
            let text = message.text
            if message.role == "user" {
                guard !text.hasPrefix("Caveat:") else { continue }
                result.prompts.append(oneLine(text, limit: 90))
            }
            // 긴 답 하나가 본문을 다 차지하지 않게 자른다.
            result.corpus.append(contentsOf: String(text.prefix(4_000)).lowercased().utf8)
            result.corpus.append(10)
        }
        return result
    }

    /// 찾는 말에서 대화를 가를 낱말만 남긴다. "세션", "찾아줘" 같은 말은 모든 대화에 들어맞는다.
    static func keywords(in query: String) -> [String] {
        let generic: Set<String> = [
            "세션", "대화", "찾아줘", "찾아", "찾기", "찾던", "만든", "만들던", "했던", "하던", "짜던", "작업",
            "그거", "그", "거", "것", "좀", "탭", "관련", "내용", "얘기", "이야기", "있던", "예전", "전에",
            "session", "chat", "find", "the", "that", "one",
        ]
        let particles = ["에서는", "에서", "으로", "이랑", "한테", "에게", "을", "를", "은", "는", "이", "가",
                         "의", "도", "과", "와", "랑", "로", "에"]
        var seen: Set<String> = []
        return query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .map { word in
                // 조사를 떼어도 두 글자 이상 남을 때만 뗀다 — "브라우저를" → "브라우저", "이"는 그대로.
                for particle in particles where word.hasSuffix(particle) && word.count - particle.count >= 2 {
                    return String(word.dropLast(particle.count))
                }
                return word
            }
            .filter { $0.count >= 2 && !generic.contains($0) && seen.insert($0).inserted }
    }

    /// 요청을 대화 처음부터 끝까지 고르게 뽑는다. 찾는 말이 든 요청은 먼저 넣는다.
    static func sample(_ prompts: [String], terms: [String], count: Int) -> [String] {
        guard prompts.count > count else { return prompts }
        var picked: [Int] = prompts.indices.filter { index in
            let lowered = prompts[index].lowercased()
            return terms.contains { lowered.contains($0) }
        }.prefix(count / 2).map { $0 }
        let remaining = count - picked.count
        if remaining > 0 {
            let step = Double(prompts.count - 1) / Double(max(1, remaining - 1))
            for slot in 0..<remaining {
                picked.append(Int((Double(slot) * step).rounded()))
            }
        }
        return Array(Set(picked)).sorted().map { prompts[$0] }
    }

    /// 찾는 말이 나온 자리 앞뒤를 조금씩. 같은 말이라도 멀리 떨어진 자리를 고른다.
    static func passages(in corpus: Data, terms: [String], limit: Int, radius: Int = 150) -> [String] {
        guard !terms.isEmpty, !corpus.isEmpty else { return [] }
        var result: [String] = []
        var taken: [Int] = []
        for term in terms {
            let needle = Data(term.utf8)
            var from = corpus.startIndex
            var perTerm = 0
            while perTerm < 2, result.count < limit,
                  let range = corpus.range(of: needle, in: from..<corpus.endIndex) {
                from = range.upperBound
                // 이미 뽑은 자리와 겹치면 건너뛴다.
                guard !taken.contains(where: { abs($0 - range.lowerBound) < radius * 2 }) else { continue }
                let lower = max(corpus.startIndex, range.lowerBound - radius)
                let upper = min(corpus.endIndex, range.upperBound + radius)
                // 바이트로 자르면 글자 가운데가 잘릴 수 있다. 깨진 끝은 버린다.
                let text = String(decoding: corpus[lower..<upper], as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FFFD}"))
                result.append("…" + oneLine(text, limit: 160) + "…")
                taken.append(range.lowerBound)
                from = min(corpus.endIndex, range.upperBound + radius * 4)
                perTerm += 1
            }
        }
        return result
    }

    private static func oneLine(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    // MARK: - Haiku에게 묻기

    static let systemPrompt = """
        You pick the one conversation, from a numbered list, that the user is looking for. \
        Each entry has a title (taken from the first request only), requests sampled across the \
        whole conversation, and passages where the searched words appear in its content. Read \
        them all and match on meaning, not on shared words alone. Prefer the conversation that \
        actually did the thing; if none did but one clearly dealt with that subject, pick it and \
        say so. If nothing fits, answer null instead of guessing. Reason in Korean, one short sentence.
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
            if !candidate.prompts.isEmpty {
                lines.append("    요청: " + candidate.prompts.map { "\"\($0)\"" }.joined(separator: " / "))
            }
            if !candidate.passages.isEmpty {
                lines.append("    본문: " + candidate.passages.joined(separator: " / "))
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
        reading: ((Double) -> Void)? = nil,
        asking: ((Int) -> Void)? = nil,
        completion: @escaping (Outcome) -> Void
    ) {
        gather(query: query, openSessionIDs: openSessionIDs(), progress: { reading?($0) }) { candidates in
            asking?(candidates.count)
            ask(query: query, candidates: candidates) { outcome in
                if shouldOpen, case .found(let candidate, _) = outcome {
                    open(candidate.conversation, from: state)
                }
                completion(outcome)
            }
        }
    }
}
