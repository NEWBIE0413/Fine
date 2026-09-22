# Fine

**English** · [한국어](README.ko.md) · [日本語](README.ja.md) · [中文](README.zh.md)

[![Fine](Assets/fine-demo.gif)](https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4)

<sub>[Watch the demo](https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4)</sub>

A quiet Mac window for the coding agents you already use.

## What it is

Claude Code, Codex, OpenCode and omp each run in their own terminal. Fine puts
them in one window, side by side, as conversations you can leave and come back
to.

Nothing is wrapped or re-implemented. Each conversation is the real agent,
running the way it does in a terminal, keeping its own history.

## Why

Four agents means four terminal windows, and nowhere that remembers which
conversation was which. Fine keeps the list — what you were doing, which agent
was doing it, how far it got — and reopens any of them where it stopped.

Pick the agent and the model when you start a conversation, or let Fine pick
from how hard your question looks.

## Install

```sh
git clone https://github.com/NEWBIE0413/Fine.git
cd Fine
./scripts/package-app.sh release
ditto .build/Fine.app /Applications/Fine.app
```

Bring the agents you want. Fine finds the ones you have.

## Setting it up

There is no settings window and no sign-in. The agents already handle their own
accounts, and Fine has a command line instead:

```sh
fine doctor          # what is ready, what is missing, and the command that fixes it
fine appearance dark # applies immediately
fine tabs            # what is open
```

It is meant to be read and driven by a coding agent as much as by you — see
[`skills/fine-setup`](skills/fine-setup/SKILL.md) for the procedure one would follow.

## License

MIT
