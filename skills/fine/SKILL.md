---
name: fine
description: Fine macOS 앱의 탭·대화·터미널을 fine CLI로 제어하거나 Fine과 tmux·원격 smux 사이에서 메시지를 주고받을 때 사용한다.
---

# Fine

앱 상태는 `fine` CLI로 읽고 바꾼다. `fine --help`에서 현재 명령을 확인하고, 먼저 `fine ping`, `fine --json windows`, `fine --json tabs`로 실행 중인 창과 탭을 찾는다. `~/.fine/window-states.json`을 직접 고치면 실행 중인 앱과 어긋난다.

## 주소와 대화

Fine 탭의 이름·ID는 `fine read <tab>`로, tmux 패널은 `%id` 또는 `tmux:label`로, 원격은 `arch:label` 또는 `mac:fine:<UUID>`로 지정한다. `fine resolve <target>`은 고정 주소를 돌려준다. `fine id`는 현재 탭의 `fine:<UUID>` 주소다. tmux 안에서는 smux 발신자가 `TMUX_PANE`을 우선하고, 그 밖의 Fine 탭에서는 `FINE_TAB_ID`를 쓴다.

```bash
fine read <target> 20
fine msg <target> '검토 결과입니다.'
fine read <target> 20
fine keys <target> Enter
```

`fine send`는 헤더 없이 글자만 입력한다. `keys Enter`는 제출이다. 둘 다 앞선 읽기를 소비하므로 다음 행동 전에 다시 읽는다. 탭·프로세스가 바뀌거나 읽은 지 600초가 지나면 거부된다. 이 상태와 trust는 tmux-bridge가 공통 관리한다.

같은 Fine 창 안은 자유롭게 대화한다. 다른 창·tmux·다른 호스트로 보내려면 대화 범위에 대한 사용자 승인을 받은 뒤 `fine trust <target>`으로 기록한다. 이미 이 대화에서 승인됐으면 다시 묻지 않는다. 수신자는 자동 역방향 trust로 답장할 수 있다. `[smux ...; reply: tmux-bridge msg mac:fine:...]`를 받으면 헤더의 전체 주소로 답장한다. 에이전트에게 제출한 뒤 답장을 기다리며 화면을 반복 조회하지 않는다.

## 화면과 대화 기록

- `fine read <tab> [lines]`: 지금 상호작용할 터미널 버퍼. 읽기 가드를 충족한다.
- `fine transcript <tab> -n 20`: Claude·Codex·OpenCode의 구조화된 대화 기록. 터미널 화면 확인이나 읽기 가드를 대신하지 않는다.
- `fine list`, `fine resume <session-id>`, `fine models`: 최근 대화, 재개, 실제 모델 선택지.

## 실행과 검증

제어 소켓은 `~/.fine/control.sock`이다. CLI가 연결되지 않으면 `fine ping`과 실행 중인 빌드부터 확인한다. 업데이트한 빌드는 앱을 다시 열어야 적용된다; 현재 작업에 재시작 승인이 있으면 그대로 진행한다.

테스트 앱은 **`FINE_HOME`으로 데이터 경로를 명시**한다. macOS Foundation은 셸의 HOME 변경만으로 격리되지 않는다. 저장소의 `scripts/test-bridge-e2e.py`는 별도 데이터·하네스 스텁·tmux 서버를 사용하며 실제 앱 소켓이 유지됐는지도 확인한다.
