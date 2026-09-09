# Fine Design System

## 1. Direction

Fine is a quiet native workspace: a light glass navigation rail beside a
single uninterrupted white terminal canvas. The memorable moment is the
material boundary itself — translucent navigation ends at one hairline, then
the conversation becomes pure paper.

Fine preserves session identities, resume behavior, model choices and terminal
output. Presentation and metadata scheduling stay separate from the child CLI.

## 2. Color and material

- `canvas`: system white (`NSColor.textBackgroundColor`)
- `ink`: system label color; terminal ANSI remains `#000000`
- `secondaryInk`: system secondary label color
- `divider`: black at 7% opacity
- `hoverFill`: black at 4% opacity
- `selectedFill`: white at 62% opacity
- `selectedRim`: white at 72% opacity
- `controlFill`: black at 5% opacity
- `controlActive`: system label color
- `sidebarMaterial`: SwiftUI `.ultraThinMaterial`
- `glassSheenTop`: white at 30% opacity
- `glassSheenMiddle`: white at 10% opacity
- `glassTintBottom`: cool system window gray at 8% opacity
- `glassEdge`: black at 8% opacity

Outside the new-conversation home, glass is restricted to the sidebar. It uses native material over a truly
transparent window, a restrained top-left luminance veil, and a one-point
refractive edge beside the workspace. It uses no outer drop shadow. The
terminal never uses blur, tint, or translucent text. The home composer uses
a translucent white surface with opaque text.

## 3. Typography

- UI body: SF Pro system, 13 pt, medium
- Section label: SF Pro system, 10 pt, semibold, +0.25 tracking
- Home title: SF Pro system, 28–34 pt, medium, -1.1 tracking
- Prompt: SF Pro system, 16 pt, regular
- Metadata: SF Pro system, 10 pt, medium, tabular where numeric
- Terminal: bundled xterm configuration and black ANSI palette
- Terminal status: SF Mono, 10 pt, medium

Korean text must remain legible without artificial uppercase transformation.

## 4. Geometry and spacing

- Base unit: 4 pt
- Sidebar width: 248 pt
- Window split gap: 0 pt
- Divider: 0 pt in layout; the sidebar draws its edge inward
- Sidebar content inset: 12 pt
- Row height: 36 pt minimum
- Row radius: 8 pt
- Compact control radius: 7 pt
- Home composer radius: 22 pt
- Home content width: 720 pt maximum; 24–48 pt adaptive outer inset
- Titlebar clearance: 40 pt
- Terminal content inset: 12 pt block, 16 pt inline
- Terminal status rail: 20 pt above an 8 pt bottom inset
- Claude footer crop: one terminal row, replaced by the Fine status rail
- Model switch popover: 330 pt wide, 16 pt internal padding
- Home model picker: 500 pt wide, 320 pt high; 128 pt provider rail,
  fixed header, and one internally scrolling model list

The app owns one fixed-height shell. Sidebar lists own their vertical scroll;
the terminal owns the remaining workspace. The white workspace remains
edge-to-edge, while terminal glyphs sit inside a quiet reading inset.

## 5. Reusable primitives and states

### `FineSplitShell`

Two columns with no gap: `GlassSidebar` at 248 pt, a one-point divider, and
`WhiteWorkspace` filling the rest.

States: home, live terminal, terminal error.

### `GlassSidebar`

Native ultra-thin material extending behind the transparent titlebar. A
three-stop luminance veil gives the glass visible depth without obscuring the
wallpaper, and the right edge draws a one-point inner boundary without taking
layout width. It contains the new-conversation action, open sessions, and
recent transcripts. Harness marks use 12 pt glyphs inside 15 pt slots.

States: normal, hover, selected, drop target.
Open conversations support local drag ordering with a subtle target outline;
reordering saves once at drop and preserves selection and the existing PTY.
VoiceOver provides move-up and move-down actions. Long names stay on one line.

### `SidebarRow`

Unboxed at rest. Hover uses `hoverFill`; selected uses `selectedFill` plus the
single-pixel `selectedRim`. Close controls appear only on hover or selection.

### `WorkspaceComposer`

One restrained white input surface with a hairline border. Model, effort,
proxy, and send controls live on the same lower baseline. No floating card
shadow and no decorative hero icon.

States: empty, focused, ready, loading catalog, router offline.

### `CompactControl`

Text-first rounded rectangle with `controlFill`, 7 pt radius, 25 pt height.
Hover increases fill slightly; active state uses ink.

### `HarnessControl`

A three-segment control at the head of the composer row: Claude, Codex, or OpenCode.
It decides which command the terminal runs and which catalog the model picker
shows. Codex launches its stock CLI without the Claude router. All harnesses
use their explicit permission-skip launch option. Switching resets the model to
that harness's default.

### `ModelPickerPanel`

A compact two-level selector instead of a single long menu. The fixed top
segment separates connected/plan models from free-tier models and disappears
when a catalog has only one tier. A narrow provider rail groups Claude, Codex,
Kimi, Gemini, Alibaba, OpenRouter, and NVIDIA explicitly; only the selected
provider's models scroll in the detail pane. Alibaba Free belongs to the free
segment, while Alibaba Plan remains in the connected segment. OpenCode shows a
single OpenCode rail entry with whatever `opencode.json` whitelists. Codex uses
its installed model catalog and persists an explicit model/effort selection.

Every catalog starts with "기본 (터미널과 동일)": no model or effort flag, no
router. That option is the terminal's plain `ccv -y`, `codex`, or `opencode`.

The panel is presented as an in-window overlay (`FineOverlay`), never as an
`NSPopover`. Two crash reports (2026-09-02, 2026-09-03) showed SwiftUI opening
the popover inside `NSHostingView.layout()`, where AppKit rebuilt the window
ordering group and a ViewBridge `NSRemoteView` observer threw. An overlay
inside the existing window cannot reach that path. The scrim is 6% black,
the card uses the workspace fill with the glass edge stroke, a 22 pt shadow,
and dismisses on scrim click or Escape.

States: connected tab, free tab, provider selected, model selected, empty
provider, default option, keyboard focus.

### `WhiteTerminal`

Edge-to-edge white xterm surface. ANSI foreground colors resolve to black.
Claude alone uses a light gray ANSI 100 prompt background and 4.5:1 minimum
text contrast; Codex and OpenCode retain the original unmodified palette.
The glyph grid uses the terminal content inset so prompts do not touch the
window edge. Fine clips Claude Code's final built-in hint row and replaces it
with a compact status rail showing the session's actual provider/model and
effort; this avoids adding a second status row. OpenCode sessions crop nothing:
that TUI draws its own input and status rows at the bottom. The status rail is interactive:
hover adds only a subtle neutral fill, and click opens a compact native model
and effort picker. Applying a selection resumes the same transcript with the
new configuration rather than creating an unrelated conversation.

States: loading/blank, interactive, resumed, error.

## 6. Motion and interaction

- Session selection: immediate; terminal views are never animated through reparenting
- Hover: opacity/fill only, 120–160 ms equivalent
- Buttons: no scale, bounce, shimmer, or perpetual animation
- Home panorama: a fixed 160 × 72 character grid. Values change at 8 fps as the
  mountain scene travels through the cells, with a seamless 180-second loop
- Cache the tiny glyph atlas and update only changed character cells. Keep one
  960 × 720 RGBA frame buffer (2.6 MiB) plus the current display image; no video
  decoder, browser engine, translating layer, or per-frame SwiftUI state
- Pause the panorama when its window is occluded/minimized, in Low Power Mode,
  or with Reduce Motion; Reduce Transparency removes the decorative layer
- Reduced-motion users receive the same layout with no essential motion loss
- Every icon button keeps a tooltip and a minimum 24 pt target

## 7. Accessibility constraints

- Text and terminal content target WCAG AA contrast on white
- Selection is communicated by fill and weight, not color alone
- Open rows have a small running-state dot and no harness mark or leading bubble.
  Recent rows retain their trailing harness mark. Open rows receive native mouse
  events across their full 37 pt height, including padding, for selection and drag.
  A single selection block slides between rows with WorkspaceManager's 0.3 s
  critically damped spring. The work area crossfades over 150 ms. Reduce Motion
  disables both. Drag targets mark the boundary above/below a row, and dropping
  inserts there without exchanging the two sessions.
- Keyboard shortcuts and native menu behavior remain unchanged
- Focusable controls use native focus handling
- Korean labels must not truncate before the close/status affordances

## 8. Accepted debt and replacement triggers

- The sidebar material uses the system compositor rather than a custom
  refraction shader. Replace only if macOS changes native material rendering or
  the sidebar becomes unreadable over common wallpapers.
- The terminal remains an xterm web view because IME and PTY behavior are
  already validated. A native text renderer is out of scope unless profiling
  identifies the web view as a material performance problem.
- Sessions run through an interactive login shell (`zsh -ilc`) so that a
  Finder-launched Fine sees the same `~/.zshrc` environment as a terminal:
  provider keys, `~/.opencode/bin` ahead of Homebrew, and the same `ccv`. The
  shell `exec`s the agent, so nothing interactive lingers. Replace with a
  captured environment snapshot only if shell startup ever becomes visible.


## New-conversation home (September 2026)

The home is a quiet opening scene: warm ivory paper, a static ASCII mountain
landscape, a milk-glass veil, and one translucent white composer. The landscape
is generated from a fixed character field and drawn with SwiftUI Canvas. It
uses no image download, timer, shader, or animation loop. A specific photograph
can replace the procedural landscape if future art direction calls for one.

The headline and supporting sentence are centered above the composer. The
composer remains bounded at 720 pt, with 22 pt text insets and a visible focus
rim. Model controls use 30 pt height and the send button uses a 34 pt target.
Harness selection moves onto its own row when the controls' ideal widths no
longer fit. Session context sits below the composer, outside the control row.
Short windows scroll the composition vertically; long prompts scroll within
the native multiline field after eight lines. Existing selection persistence,
model discovery, submission, terminal sessions, and sidebar styling are retained.

Reduce Transparency removes the decorative ASCII layers and makes the composer
opaque. Decorative drawing ignores hits and is hidden from accessibility.
The model picker retains its existing in-window overlay to avoid the AppKit
popover crash path. HomePresentationTests render minimum, normal, and wide
workspace sizes plus a long-input state to
`.build/home-design-review/` for visual inspection.


## Mixed-harness recent conversations

Recent rows share one chronological list across Claude, Codex, and OpenCode.
The text begins at the row inset; a relative timestamp and a 15 pt monochrome
vector logo sit at the right edge. Each logo occupies a fixed 18 pt slot, so
long titles truncate before the metadata. The native button exposes both title
and harness to accessibility and shows them in its tooltip. Template assets
follow the interface ink; no brand colors or raster images are used.

## 9. Resource budget and demand loading

- Recent conversations initially publish 30 rows. The lazy list requests the next
  30 at its end; one extra record determines whether another page exists.
- Claude transcript bodies are read only for the requested window of titles and
  explicitly open older sessions. Unchanged files read zero body bytes; append
  updates read only new bytes in 64 KiB chunks. Cache only short titles, file
  identity/offsets, and an unfinished line capped at 256 KiB. Oversized tool
  records are skipped and large completed-line buffers are released.
- Transcript discovery still enumerates filename/mtime metadata for sorting.
  The first read of a requested transcript scans the file to preserve its latest
  summary. If first-page I/O becomes material, replace this with a persistent
  title index; do not silently drop older summary records.
- Native Codex/OpenCode queries use read-only SQLite cursors and stop after the
  requested number of valid titles, including past placeholder/empty titles.
- Coalesce overlapping recent scans. Pause periodic file/database and model
  catalog refreshes while all Fine windows are hidden; unresolved session IDs
  may still be detected so restoration remains reliable.
- Hidden terminal output crosses the WebKit bridge at 100 ms intervals. Visible
  typing echoes remain immediate; active redraws keep existing 8 ms coalescing
  and cursor/IME transaction guards. No CLI output is discarded. Large one-off
  output buffers are released after delivery, and unchanged layouts skip refit.
- Keep xterm's existing bounded scrollback and render only the selected terminal.
  The CLI owns transcript loading; Fine does not load a second message history.

## Model selection polish

Harness and model controls share a 30 pt height. A moving selection surface
connects harness changes; picker presentation uses a restrained fade and scale.
Single-provider catalogs omit the provider rail, large catalogs offer search,
and model labels wrap to two lines. The composer uses a borderless glass surface.
Reduce Motion removes decorative movement.

Codex runtime resume identity follows the unique writable rollout in the PTY process
group (including npm's native child). Read-only history and overlapping writers
never replace the saved identity. This also updates the next relaunch after
`/resume` or a fork. The existing metadata timer performs this bounded local
lookup; if its cost becomes material, replace lsof with native process-FD queries.
