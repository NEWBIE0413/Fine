# Fine

[English](README.md) · **한국어** · [日本語](README.ja.md) · [中文](README.zh.md)

[![Fine](Assets/fine-demo.gif)](https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4)

<sub>[데모 보기](https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4)</sub>

이미 쓰고 있는 코딩 에이전트를 한 창에 모아두는 맥 앱.

## 무엇인가

Claude Code, Codex, OpenCode, omp는 각자 자기 터미널에서 돕니다. Fine은 그것들을
한 창에 나란히 놓고, 나갔다가 다시 돌아올 수 있는 대화로 다룹니다.

감싸거나 다시 만들지 않았습니다. 각 대화는 터미널에서 돌던 그 에이전트 그대로고,
자기 기록도 그대로 들고 있습니다.

## 왜

에이전트가 넷이면 터미널 창도 넷이고, 어느 대화가 무엇이었는지 기억하는 곳은
없습니다. Fine이 그 목록을 들고 있습니다 — 무엇을 하던 중이었고, 어떤 에이전트가
하고 있었고, 어디까지 갔는지. 그리고 멈춘 자리에서 다시 엽니다.

대화를 시작할 때 에이전트와 모델을 고르거나, 질문의 난이도를 보고 Fine이 고르게
둘 수 있습니다.

## 설치

```sh
git clone https://github.com/NEWBIE0413/Fine.git
cd Fine
./scripts/package-app.sh release
ditto .build/Fine.app /Applications/Fine.app
```

쓰고 싶은 에이전트만 있으면 됩니다. 깔려 있는 것을 Fine이 찾습니다.

## 설정

설정창도 로그인도 없습니다. 계정은 에이전트들이 이미 각자 들고 있고, Fine에는
대신 명령줄이 있습니다:

```sh
fine doctor          # 무엇이 준비됐고, 무엇이 빠졌고, 그것을 채우는 명령
fine appearance dark # 바로 적용됩니다
fine tabs            # 무엇이 열려 있나
```

사람이 읽어도 되고, 코딩 에이전트가 그대로 실행해도 되게 만들었습니다 —
에이전트가 따라갈 절차는 [`skills/fine-setup`](skills/fine-setup/SKILL.md)에 있습니다.

## 라이선스

MIT
