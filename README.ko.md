<div align="center">

<img src="Assets/fine-1024.png" width="96" alt="">

# Fine

**쓰던 코딩 에이전트를 한 창에 모아두는 맥 앱.**

[English](README.md) · 한국어 · [日本語](README.ja.md) · [中文](README.zh.md)

<a href="https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4">
  <img src="Assets/fine-demo.gif" width="720" alt="">
</a>

<sub>눌러서 데모 보기</sub>

</div>

---

## 하는 일

Claude Code, Codex, OpenCode, omp는 각자 자기 터미널에서 돕니다. Fine은 이것들을
한 창에 모아, 나갔다가 다시 돌아올 수 있는 대화로 다룹니다.

감싸거나 새로 만든 게 아닙니다. 어느 대화든 터미널에서 돌던 그 에이전트 그대로고,
쌓아둔 기록도 그대로입니다.

## 왜 만들었나

에이전트가 넷이면 터미널도 넷인데, 어느 대화가 무슨 일이었는지 기억하는 곳은
없습니다. Fine이 그걸 들고 있습니다. 무엇을 하던 중이었는지, 어떤 에이전트였는지,
어디까지 갔는지. 그리고 멈춘 자리에서 다시 엽니다.

시작할 때 에이전트와 모델을 직접 고르거나, 질문이 얼마나 어려운지 보고 Fine이
고르게 둘 수 있습니다.

## 설치

```sh
git clone https://github.com/NEWBIE0413/Fine.git
cd Fine
./scripts/package-app.sh release
ditto .build/Fine.app /Applications/Fine.app
```

쓰던 에이전트만 있으면 됩니다. 깔려 있는 걸 Fine이 알아서 찾습니다.

## 설정

설정창도 로그인도 없습니다. 계정은 에이전트들이 각자 들고 있으니까요. 대신
명령줄이 있습니다.

```sh
fine doctor            # 뭐가 준비됐고 뭐가 빠졌는지, 그리고 채우는 방법
fine appearance dark   # 바로 반영됩니다
fine tabs              # 지금 뭐가 열려 있는지
```

사람이 읽어도 되고 코딩 에이전트가 그대로 실행해도 됩니다.
에이전트가 따라갈 절차는 [`skills/fine-setup`](skills/fine-setup/SKILL.md)에 있습니다.

<div align="center"><sub>MIT</sub></div>
