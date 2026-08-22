# Fine Design System

## 1. Direction

Fine is a quiet native workspace: a light glass navigation rail beside a
single uninterrupted white terminal canvas. The memorable moment is the
material boundary itself — translucent navigation ends at one hairline, then
the conversation becomes pure paper.

The redesign keeps every existing session, resume, model, and terminal
behavior. It changes only the presentation layer.

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

Glass is restricted to the sidebar. It uses native material over a truly
transparent window, a restrained top-left luminance veil, and a one-point
refractive edge beside the workspace. It uses no outer drop shadow. The
terminal and composer workspace never use blur, tint, or translucent text.

## 3. Typography

- UI body: SF Pro system, 13 pt, medium
- Section label: SF Pro system, 10 pt, semibold, +0.25 tracking
- Home title: SF Pro system, 24 pt, semibold, -0.45 tracking
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
- Composer radius: 14 pt
- Home content width: 680 pt maximum
- Titlebar clearance: 40 pt
- Terminal content inset: 12 pt block, 16 pt inline
- Terminal status rail: 20 pt above an 8 pt bottom inset
- Claude footer crop: one terminal row, replaced by the Fine status rail

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
recent transcripts.

States: normal, hover, selected, running, stopped.

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

### `WhiteTerminal`

Edge-to-edge white xterm surface. ANSI foreground colors resolve to black.
The glyph grid uses the terminal content inset so prompts do not touch the
window edge. Fine clips Claude Code's final built-in hint row and replaces it
with a compact status rail showing the session's actual provider/model and
effort; this avoids adding a second status row.

States: loading/blank, interactive, resumed, error.

## 6. Motion and interaction

- Selection changes: native spring, response 0.28, damping 1.0
- Hover: opacity/fill only, 120–160 ms equivalent
- Buttons: no scale, bounce, shimmer, or perpetual animation
- Reduced-motion users receive the same layout with no essential motion loss
- Every icon button keeps a tooltip and a minimum 24 pt target

## 7. Accessibility constraints

- Text and terminal content target WCAG AA contrast on white
- Selection is communicated by fill and weight, not color alone
- Running state has a dot plus session context; it is not the only selection cue
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
