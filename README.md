<div align="center">

<img src="Assets/fine-1024.png" width="96" alt="">

# Fine

**A quiet Mac window for the coding agents you already use.**

English · [한국어](README.ko.md) · [日本語](README.ja.md) · [中文](README.zh.md)

<a href="https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4">
  <img src="Assets/fine-demo.gif" width="720" alt="">
</a>

<sub>Click to watch the demo</sub>

</div>

---

## What it does

Claude Code, Codex, OpenCode and omp each live in their own terminal. Fine puts
them in one window as conversations you can leave and come back to.

Nothing is wrapped or reimplemented. Each conversation is the real agent,
running the way it runs in a terminal, keeping its own history.

## Why

Four agents means four terminal windows and nowhere that remembers which
conversation was which. Fine keeps that list — what you were doing, which agent
was doing it, how far it got — and reopens any of them where it stopped.

Choose the agent and the model when you start, or let Fine choose from how hard
the question looks.

## Install

```sh
git clone https://github.com/NEWBIE0413/Fine.git
cd Fine
./scripts/package-app.sh release
ditto .build/Fine.app /Applications/Fine.app
```

Bring the agents you want. Fine finds the ones you have.

## Setting up

No settings window, no sign-in. Each agent already keeps its own account, and
Fine gives you a command line instead:

```sh
fine doctor            # what is ready, what is missing, how to fix it
fine appearance dark   # applies immediately
fine tabs              # what is open
```

Written to be read and run by a coding agent as much as by you —
[`skills/fine-setup`](skills/fine-setup/SKILL.md) is the procedure one follows.

<div align="center"><sub>MIT</sub></div>
