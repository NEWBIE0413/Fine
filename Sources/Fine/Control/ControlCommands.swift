import AppKit
import Foundation

/// `fine` CLI 명령 라우터. UI가 할 수 있는 일은 전부 여기서도 할 수 있어야 한다 —
/// 새 UI 기능을 추가하면 같은 커밋에서 명령도 추가한다.
@MainActor
enum ControlCommands {
    nonisolated static let socketPath = FinePaths.home.appendingPathComponent(".fine/control.sock").path

    static func handle(_ request: ControlRequest, completion: @escaping (ControlResponse) -> Void) {
        do {
            if try dispatchAsync(request, completion: completion) { return }
            completion(.ok(try dispatch(request)))
        } catch let error as CommandError {
            completion(.error(error.message))
        } catch let error as ControlArgumentError {
            completion(.error(error.message))
        } catch {
            completion(.error("\(error)"))
        }
    }

    struct CommandError: Error { let message: String }
    private static func fail(_ message: String) -> CommandError { CommandError(message: message) }

    // MARK: - 동기 명령

    private static func dispatch(_ r: ControlRequest) throws -> Any {
        switch r.command {
        case "ping":
            return [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "dev",
                "windows": liveWindows().count,
            ]

        case "windows.list":
            return liveWindows().enumerated().map { describe($0.element, index: $0.offset) }

        case "window.focus":
            let (entry, index) = try window(r)
            focus(entry)
            return describe(entry, index: index)

        case "window.close":
            let (entry, _) = try window(r)
            guard let nsWindow = entry.window else { throw fail("window has no NSWindow yet") }
            nsWindow.performClose(nil)
            return ["closed": entry.state.windowStateID.uuidString]

        case "tab.list":
            let targets: [(WindowEntry, Int)] = r.string("window") == nil
                ? liveWindows().enumerated().map { ($0.element, $0.offset) }
                : [try window(r)]
            return targets.flatMap { entry, windowIndex in
                entry.state.sessions.enumerated().map { describe($0.element, index: $0.offset, in: entry, windowIndex: windowIndex) }
            }

        case "tab.info":
            let (entry, windowIndex, session, tabIndex) = try tab(r)
            return describe(session, index: tabIndex, in: entry, windowIndex: windowIndex)

        case "tab.select":
            let (entry, windowIndex, session, _) = try tab(r)
            entry.state.selectSession(session)
            if r.bool("focus") ?? true { focus(entry) }
            return describe(session, index: index(of: session, in: entry), in: entry, windowIndex: windowIndex)

        case "tab.rename":
            let (entry, windowIndex, session, _) = try tab(r)
            guard let name = r.string("name"), !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw fail("usage: fine rename <tab> <name>")
            }
            // "auto"는 이름을 지우고 하네스가 만드는 제목으로 되돌린다.
            if name == "auto" {
                session.clearCustomName()
            } else {
                session.rename(to: name)
            }
            return describe(session, index: index(of: session, in: entry), in: entry, windowIndex: windowIndex)

        case "tab.close":
            let (entry, _, session, _) = try tab(r)
            entry.state.removeSession(session)
            return ["closed": session.id.uuidString]

        case "tab.next", "tab.prev":
            let (entry, windowIndex) = try window(r)
            if r.command == "tab.next" { entry.state.selectNextSession() } else { entry.state.selectPreviousSession() }
            if r.bool("focus") ?? true { focus(entry) }
            guard let session = entry.state.selectedSession else { throw fail("no tabs") }
            return describe(session, index: index(of: session, in: entry), in: entry, windowIndex: windowIndex)

        case "tab.move":
            let (entry, windowIndex, session, current) = try tab(r)
            guard let spec = r.string("to") else { throw fail("to required (index, +1, -1)") }
            guard let destination = ControlTargetResolver.moveDestination(
                spec: spec, current: current, count: entry.state.sessions.count
            ) else { throw fail("destination out of range: \(spec) (\(entry.state.sessions.count) tabs)") }
            if destination != current {
                entry.state.moveSession(id: session.id, to: entry.state.sessions[destination].id)
            }
            return entry.state.sessions.enumerated().map { describe($0.element, index: $0.offset, in: entry, windowIndex: windowIndex) }

        case "tab.restart":
            let (entry, windowIndex, session, _) = try tab(r)
            guard session.configuration.harness != .opencode else {
                throw fail("OpenCode sessions cannot be restarted with another model (same limit as the UI picker)")
            }
            guard session.resumableSessionID != nil else {
                throw fail("tab has no conversation id yet — send a first message, then retry")
            }
            let current = session.configuration
            let configuration = try ControlArguments.configuration(
                base: current, harness: nil, model: r.string("model"), effort: r.string("effort"), proxy: current.proxyEnabled
            )
            // UI의 모델 피커는 항상 선택된 탭을 재시작한다. 선택되지 않은 탭을 그대로
            // 넘기면 교체본이 시작되지 않은 채 남으므로 먼저 선택해 같은 경로를 탄다.
            entry.state.selectSession(session)
            guard entry.state.restartSession(session, with: configuration) else { throw fail("restart failed") }
            guard let replacement = entry.state.selectedSession else { throw fail("restart produced no session") }
            if r.bool("focus") ?? true { focus(entry) }
            return describe(replacement, index: index(of: replacement, in: entry), in: entry, windowIndex: windowIndex)

        case "tab.write":
            let (entry, windowIndex, session, tabIndex) = try tab(r)
            guard let text = r.string("text") else { throw fail("text required") }
            try requireFingerprint(r, session)
            guard session.write(Data(text.utf8)) else { throw fail("tab process is not running") }
            return describe(session, index: tabIndex, in: entry, windowIndex: windowIndex)

        case "tab.keys":
            let (entry, windowIndex, session, tabIndex) = try tab(r)
            guard let names = r.args["keys"] as? [String], !names.isEmpty else { throw fail("keys required") }
            var payload = Data()
            for name in names {
                guard let bytes = ControlKeys.bytes(for: name) else { throw fail("unknown key: \(name)") }
                payload.append(bytes)
            }
            try requireFingerprint(r, session)
            guard session.write(payload) else { throw fail("tab process is not running") }
            return describe(session, index: tabIndex, in: entry, windowIndex: windowIndex)

        case "home":
            let (entry, index) = try window(r)
            entry.state.showHome()
            if r.bool("focus") ?? true { focus(entry) }
            return describe(entry, index: index)

        case "appearance":
            // 값이 없으면 현재 상태만 알려준다. 있으면 저장하고 즉시 적용한다 —
            // UserDefaults만 쓰면 실행 중인 앱은 그 변화를 모른다.
            if let value = r.string("mode") {
                guard let appearance = FineAppearance(rawValue: value) else {
                    throw fail("unknown appearance: \(value) (system|light|dark)")
                }
                UserDefaults.standard.set(appearance.rawValue, forKey: FineAppearance.storageKey)
                FineAppearance.apply(appearance)
            }
            let current = FineAppearance.stored
            return [
                "mode": current.rawValue,
                "title": current.title,
                "app": NSApp.appearance?.name.rawValue ?? "nil(시스템 따름)",
                "key": NSApp.keyWindow?.effectiveAppearance.name.rawValue ?? "none",
                "windows": NSApp.windows.map { window in
                    [
                        "title": window.title,
                        "class": String(describing: type(of: window)),
                        "set": window.appearance?.name.rawValue ?? "nil",
                        "effective": window.effectiveAppearance.name.rawValue,
                        "visible": window.isVisible,
                    ] as [String: Any]
                },
            ]

        case "doctor":
            return FineDoctor.run()

        case "state.dump":
            let data = try JSONEncoder.pretty.encode(WindowStateStorage.shared.states)
            return try JSONSerialization.jsonObject(with: data)

        case "appearance.toggle", "session.find", "conversations.list", "models.list", "session.new", "session.resume", "window.new", "tab.read", "tab.theme", "tab.transcript":
            throw fail("internal: async command reached sync dispatcher")
        default:
            throw fail("unknown command: \(r.command)")
        }
    }

    // MARK: - 비동기 명령 (창을 열거나, 디스크·네트워크를 읽어야 하는 것들)

    /// 처리했으면 true. 창 생성은 SwiftUI가 다음 run loop에서 AppState를 만들기 때문에
    /// 레지스트리에 새 창이 등록될 때까지 폴링한 뒤 응답한다.
    private static func dispatchAsync(_ r: ControlRequest, completion: @escaping (ControlResponse) -> Void) throws -> Bool {
        switch r.command {
        case "window.new":
            openWindow { entry in
                completion(entry.map { .ok(describe($0, index: liveWindows().count - 1)) } ?? .error("window did not appear"))
            }
            return true

        case "appearance.toggle":
            // 사이드바의 토글과 같은 길: 토글 자리에서 파문을 일으키고, 끝나면 잰 값을 돌려준다.
            let window = NSApp.keyWindow ?? liveWindows().first?.window
            let isDark = (window?.effectiveAppearance ?? NSApp.effectiveAppearance)
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let next: FineAppearance = isDark ? .light : .dark
            let apply = {
                UserDefaults.standard.set(next.rawValue, forKey: FineAppearance.storageKey)
                FineAppearance.apply(next)
            }
            let origin = ThemeTransition.toggleCenter ?? CGPoint(x: FineTheme.sidebarWidth - 24, y: 56)
            let rippled = ThemeTransition.ripple(from: origin, in: window, applying: apply) { timing in
                completion(.ok(timing.dictionary.merging(["mode": next.rawValue, "ripple": true]) { $1 }))
            }
            if !rippled { completion(.ok(["mode": next.rawValue, "ripple": false])) }
            return true

        case "session.find":
            guard let query = r.string("query"), !query.isEmpty else { throw fail("query required") }
            let (entry, _) = try window(r)
            let shouldOpen = r.bool("open") ?? true
            let started = Date()
            var count = 0
            SessionFinder.find(query, from: entry.state, open: shouldOpen, asking: { count = $0 }) { outcome in
                var result: [String: Any] = [
                    "query": query, "candidates": count, "ms": Int(Date().timeIntervalSince(started) * 1000),
                ]
                switch outcome {
                case .found(let candidate, let reason):
                    result["found"] = true
                    result["id"] = candidate.conversation.id
                    result["title"] = candidate.conversation.title
                    result["harness"] = candidate.conversation.harness.rawValue
                    result["wasOpen"] = candidate.isOpen
                    result["opened"] = shouldOpen
                    result["reason"] = reason
                    if shouldOpen, r.bool("focus") ?? true { NSApp.activate(ignoringOtherApps: true) }
                case .notFound(let reason):
                    result["found"] = false
                    result["reason"] = reason
                case .failed(let message):
                    completion(.error(message))
                    return
                }
                completion(.ok(result))
            }
            return true

        case "tab.theme":
            let (_, _, session, _) = try tab(r)
            guard session.hasTerminal else { throw fail("tab has no terminal yet (not started)") }
            session.readTheme { text in
                completion(text.map { .ok(["theme": $0]) } ?? .error("terminal not ready"))
            }
            return true

        case "tab.read":
            let (_, _, session, _) = try tab(r)
            guard session.hasTerminal else { throw fail("tab has no terminal yet (not started)") }
            session.readScreen(lines: r.int("lines") ?? 50) { text in
                completion(text.map { .ok(["text": $0]) } ?? .error("terminal not ready"))
            }
            return true

        case "tab.transcript":
            let (_, _, session, _) = try tab(r)
            guard let sessionID = session.resumableSessionID else {
                throw fail("tab has no conversation id yet — the harness has not written a session")
            }
            let harness = session.configuration.harness
            let limit = min(500, max(1, r.int("limit") ?? 20))
            DispatchQueue.global(qos: .utility).async {
                guard let messages = HarnessTranscript.messages(harness: harness, sessionID: sessionID, limit: limit) else {
                    completion(.error("transcript not found for \(harness.rawValue) session \(sessionID)")); return
                }
                completion(.ok(["harness": harness.rawValue, "sessionId": sessionID, "messages": messages.map(\.json)] as [String: Any]))
            }
            return true

        case "conversations.list":
            let limit = r.int("limit") ?? 30
            let harness = try ControlArguments.harness(r.string("harness"))
            // 전체 스캔은 transcript 메타데이터를 다시 읽는다. 창의 스캐너는 페이지만 갖고
            // 있어 `-n 200` 같은 요청을 못 채우므로, CLI는 유틸리티 큐에서 별도 스캔한다.
            DispatchQueue.global(qos: .utility).async {
                let dir = QuickConversationScanner.defaultTranscriptsDirectory()
                let rows = QuickConversationScanner.scan(directory: dir, sessionStore: .local)
                    .filter { harness == nil || $0.harness == harness }
                    .prefix(limit)
                    .map(describe)
                completion(.ok(Array(rows)))
            }
            return true

        case "models.list":
            let harness = try ControlArguments.harness(r.string("harness")) ?? QuickComposerPreferences.load().harness
            let catalog = QuickModelCatalog()
            catalog.refresh(harness: harness)
            // isLoading이 내려갈 때까지 폴링. OpenCode 검색은 최대 20초라 여유를 둔다.
            Task { @MainActor in
                for _ in 0..<250 where catalog.isLoading {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                completion(.ok([
                    "harness": harness.rawValue,
                    "routerAvailable": catalog.routerAvailable,
                    "models": catalog.models.map { m in
                        ["id": m.id, "displayName": m.displayName, "efforts": m.supportedEfforts.map(\.rawValue)] as [String: Any]
                    },
                ] as [String: Any]))
            }
            return true

        case "session.new", "session.resume":
            let run: (WindowEntry, Int) -> Void = { entry, windowIndex in
                do {
                    if r.command == "session.resume" {
                        guard let id = r.string("id"), !id.isEmpty else { throw fail("id required") }
                        try resume(id: id, harnessRaw: r.string("harness"), in: entry)
                    } else {
                        let configuration = try ControlArguments.configuration(
                            base: QuickComposerPreferences.load(),
                            harness: r.string("harness"), model: r.string("model"),
                            effort: r.string("effort"), proxy: r.bool("proxy")
                        )
                        entry.state.addSession(initialPrompt: r.string("prompt"), configuration: configuration)
                    }
                    if r.bool("focus") ?? true { focus(entry) }
                    guard let session = entry.state.selectedSession else { throw fail("session not created") }
                    completion(.ok(describe(session, index: index(of: session, in: entry), in: entry, windowIndex: windowIndex)))
                } catch let error as CommandError {
                    completion(.error(error.message))
                } catch let error as ControlArgumentError {
                    completion(.error(error.message))
                } catch {
                    completion(.error("\(error)"))
                }
            }
            if let (entry, index) = try? window(r) {
                run(entry, index)
            } else if r.string("window") != nil {
                throw fail("window not found: \(r.string("window") ?? "")")
            } else {
                openWindow { entry in
                    guard let entry else { completion(.error("could not open a window")); return }
                    run(entry, liveWindows().count - 1)
                }
            }
            return true
        default:
            return false
        }
    }

    /// `fine resume <id>`: 열려 있는 탭이면 선택하고, 아니면 저장된 구성(없으면 하네스
    /// 기본값)으로 이어 연다. 하네스는 `--harness`, 없으면 저장된 구성, 없으면 ID 모양으로
    /// 추정한다 — `ses_…`는 OpenCode, Codex 스토어에 있으면 Codex, 나머지는 Claude.
    private static func resume(id: String, harnessRaw: String?, in entry: WindowEntry) throws {
        if let existing = entry.state.sessions.first(where: { $0.matchesConversation(sessionId: id) }) {
            entry.state.selectSession(existing)
            return
        }
        let saved = QuickSessionConfigurationStorage.shared.configuration(for: id)
        let harness: QuickHarness
        if let explicit = try ControlArguments.harness(harnessRaw) {
            harness = explicit
        } else if let saved {
            harness = saved.harness
        } else if id.hasPrefix("ses_") {
            harness = .opencode
        } else if HarnessSessionStore.local.metadata(harness: .codex, sessionID: id) != nil {
            harness = .codex
        } else {
            harness = .claude
        }
        guard QuickSessionIdentifier.isValid(id, for: harness) else {
            throw fail("\(id) is not a valid \(harness.title) session id")
        }
        let configuration = (saved?.harness == harness ? saved : nil) ?? .defaultConfiguration(for: harness)
        entry.state.addSession(resumeSessionId: id, configuration: configuration)
        // Claude 제목은 창의 스캐너가 이미 읽어 둔 ai-title에서, 나머지는 하네스 스토어에서.
        if let title = QuickConversationScanner.shared.aiTitlesBySessionId[id]
            ?? HarnessSessionStore.local.metadata(harness: harness, sessionID: id)?.title {
            entry.state.selectedSession?.name = title
        }
    }

    private static func openWindow(completion: @escaping (WindowEntry?) -> Void) {
        guard let open = WindowOpener.open else { completion(nil); return }
        let before = Set(liveWindows().map { $0.state.windowStateID })
        let id = UUID()
        open(id)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            for _ in 0..<40 {
                if let entry = liveWindows().first(where: { $0.state.windowStateID == id || !before.contains($0.state.windowStateID) }) {
                    completion(entry); return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            completion(nil)
        }
    }

    // MARK: - 대상 해석

    typealias WindowEntry = (state: AppState, window: NSWindow?)

    static func liveWindows() -> [WindowEntry] {
        FineWindowRegistry.shared.liveEntries()
    }

    private static func window(_ r: ControlRequest) throws -> (WindowEntry, Int) {
        let entries = liveWindows()
        guard !entries.isEmpty else { throw fail("no windows open (fine window new)") }
        let descriptors = entries.map {
            ControlTargetResolver.WindowDescriptor(id: $0.state.windowStateID, isKey: $0.window?.isKeyWindow ?? false)
        }
        guard let index = ControlTargetResolver.windowIndex(query: r.string("window"), in: descriptors) else {
            throw fail("window not found: \(r.string("window") ?? "")")
        }
        return (entries[index], index)
    }

    /// `-w`가 있으면 그 창 안에서만, 없으면 front 창부터 모든 창을 차례로 찾는다.
    private static func tab(_ r: ControlRequest) throws -> (WindowEntry, Int, TerminalSession, Int) {
        guard let query = r.string("tab"), !query.isEmpty else { throw fail("tab required") }
        let candidates: [(WindowEntry, Int)]
        if r.string("window") != nil {
            candidates = [try window(r)]
        } else {
            let all = liveWindows().enumerated().map { ($0.element, $0.offset) }
            let front = try? window(r)
            candidates = all.sorted { lhs, _ in lhs.1 == front?.1 }
        }
        for (entry, windowIndex) in candidates {
            let descriptors = entry.state.sessions.map {
                ControlTargetResolver.TabDescriptor(id: $0.id, name: $0.name, conversationID: $0.resumableSessionID)
            }
            if let index = ControlTargetResolver.tabIndex(query: query, in: descriptors) {
                return (entry, windowIndex, entry.state.sessions[index], index)
            }
        }
        throw fail("tab not found: \(query)")
    }

    private static func requireFingerprint(_ request: ControlRequest, _ session: TerminalSession) throws {
        if let expected = request.string("fingerprint"), expected != session.controlFingerprint {
            throw fail("tab process was replaced since read; read it again")
        }
    }

    private static func index(of session: TerminalSession, in entry: WindowEntry) -> Int {
        entry.state.sessions.firstIndex(of: session) ?? -1
    }

    private static func focus(_ entry: WindowEntry) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = entry.window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - 직렬화

    private static func describe(_ entry: WindowEntry, index: Int) -> [String: Any] {
        [
            "index": index,
            "id": entry.state.windowStateID.uuidString,
            "isKey": entry.window?.isKeyWindow ?? false,
            "title": entry.state.windowTitle,
            "tabCount": entry.state.sessions.count,
            "selectedTab": entry.state.selectedSession?.id.uuidString ?? "",
        ]
    }

    private static func describe(_ s: TerminalSession, index: Int, in entry: WindowEntry, windowIndex: Int) -> [String: Any] {
        [
            "index": index,
            "id": s.id.uuidString,
            "name": s.name,
            "harness": s.configuration.harness.rawValue,
            "model": s.configuration.modelID,
            "effort": s.configuration.effort.rawValue,
            "proxy": s.configuration.proxyEnabled,
            "sessionId": s.resumableSessionID ?? "",
            "running": s.isRunning,
            "fingerprint": s.controlFingerprint,
            "selected": entry.state.selectedSession?.id == s.id,
            "window": entry.state.windowStateID.uuidString,
            "windowIndex": windowIndex,
        ]
    }

    nonisolated private static func describe(_ c: QuickConversation) -> [String: Any] {
        [
            "id": c.id,
            "harness": c.harness.rawValue,
            "title": c.aiTitle ?? c.title,
            "modifiedAt": iso(c.modifiedAt),
            "transcript": c.transcriptURL?.path ?? "",
        ]
    }

    nonisolated private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }
}
