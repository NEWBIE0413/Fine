# Fine — 실제 소스 저장소 (canonical)

`/Applications/Fine.app`에 설치되는 앱은 **이 저장소**에서 빌드한다.

```sh
swift test
./scripts/package-app.sh release
ditto .build/Fine.app /Applications/Fine.app
```

`~/cld/Fine-design`은 2026-09-09 시점의 **디자인 스냅샷 포크**다. UI 시안 전용이고,
`fine` CLI·제어 소켓·smux 브리지가 없다. 거기서 빌드한 앱을 설치하면 안 된다.

## 재시작 주의

Fine 안에서 도는 에이전트가 Fine을 종료하면 자기 세션이 끊긴다.
재시작 전에 `fine --json tabs`로 세션 ID를 남기고, 사용자에게 재개 방법을 알린 뒤 진행한다.

- 프로세스 이름이 전체 경로라 `pkill -x Fine`은 매칭되지 않는다. PID로 잡을 것.
- macOS에는 `setsid`가 없다. 백그라운드 재시작 스크립트에 쓰면 조용히 실패한다.

## 홈 화면 배경

다크 모드 홈 위쪽 장면은 `~/.fine/home-scene.png`에 파일을 두면 바뀐다 (빌드 불필요).
번들 에셋 경로 `HarnessIcons.xcassets/HomeScene.imageset/`은 `.gitignore`에 있다 —
남의 그림을 공개 저장소에 싣지 않기 위해서다. 자세한 내용은 `docs/home-scene.md`.
