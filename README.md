# Fine

![Fine app icon](Assets/fine-1024.png)

Fine is a native macOS window for everyday Claude Code conversations. It starts each conversation in a direct PTY without creating a project or a persistent terminal session.

## Features

- A composer home with model, effort, and optional local proxy controls
- Claude and Codex models through the local router at `127.0.0.1:4141`
- Open conversation tabs and recent Claude transcript history
- Resume by Claude session ID, with reuse when the conversation is already open
- Claude-generated `ai-title` values for tab and window titles
- A light xterm.js terminal with WebGL rendering and native macOS IME handling
- Per-window position, size, zoom, and full-screen restoration

Conversation processes are intentionally ephemeral. Fine restores windows but does not restart tabs after the app exits. Claude transcripts remain available for resume.

## Requirements

- macOS 14 or later
- Claude Code CLI
- The `ccv` wrapper at `~/myworld/ccv`
- A writable conversation directory at `~/cld`

The model picker reads the installed Claude CLI catalog. Codex models require the optional local router on port 4141 and the same environment contract used by `ccv`.

## Build and test

```sh
swift test
./scripts/package-app.sh release
```

The packaging script creates and ad-hoc signs `.build/Fine.app`. To install it:

```sh
cp -R .build/Fine.app /Applications/Fine.app
open /Applications/Fine.app
```

## Keyboard shortcuts

- `Command-N`: new Fine window
- `Command-T`: start a blank conversation immediately
- `Command-Shift-[` / `Command-Shift-]`: previous or next open conversation

## License

MIT. See [LICENSE](LICENSE).
