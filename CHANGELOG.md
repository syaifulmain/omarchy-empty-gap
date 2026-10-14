# Changelog

## 0.7.0 — Gap buttons, one cursor, direct height typing

- **Panel rework**: the top of the popup is a diamond of five icon buttons
  — the edge arrows `↑ ← → ↓` around the master — laid out in the same 3x3
  shape as the screen edges they toggle. Each edge button toggles its strip
  and stays accent-tinted while that strip is on; the four edge buttons carry
  no text label, while the centre button reads `On` / `Off` with the master
  state and enables or disables every strip at once.
- **All four configuration rows are always listed** (Top, Right, Bottom,
  Left) instead of only the enabled edges, so height and transparency can
  be set before a strip is switched on. A disabled edge is dimmed but stays
  editable.
- **One cursor shared by keyboard and mouse**, following the kit's
  `hasCursor` convention: hover moves the cursor, the keyboard moves the
  cursor, and the highlight derives from the cursor alone — so exactly one
  control is lit at any time.
- **Fixed the highlight that covered a whole section**: a Repeater delegate
  that declares a required property receives no context properties, so the
  rows' bare `index` stayed undefined and every row resolved to index 0 —
  one hovered control lit up every row at once. `index` is now declared as
  a required property alongside `modelData`.
- **Accent cursor ring** around the focused control: the kit's
  `hover-cursor` chrome is softer than a bordered control's idle chrome in
  some themes (0.25 border alpha against 0.4), which read as "less" right
  when the cursor arrived.
- **Status line** under the rows names the current target
  (`Top · height slider`) and the keys that act on it, so the cursor
  position is never a guess.
- **Type the height directly**: with the cursor — or just the pointer —
  on a height input, digits set that strip's height immediately, with no
  Space and no inline text editor. Digits typed together are buffered
  (`5` then `0` is 50), `Backspace` takes the last digit back, and
  `Space` starts a fresh number. This replaces the old path that focused
  the SpinBox, which never committed what was typed.
- **Full keyboard navigation**: `↑↓←→` or `hjkl` walk the button diamond, then
  the configuration rows and their three controls; `Space` toggles the focused
  gap or switch and enters the slider/number editor; `Escape` leaves the
  editor or closes the popup; the focused control is scrolled into view; and
  `Tab` / `Shift + Tab` hop to the next/previous bar widget. The cursor starts
  on the **Top** gap button when the panel opens.
- **No keybinding is registered**: the plugin spawns no external process and
  never edits `~/.config/hypr/`, so it cannot shadow or evict a binding you
  already use. Want a keyboard toggle for the panel? Add one yourself — see
  the README.

## 0.6.0 — Bar icon controls

- **Left click** opens the settings popup.
- **Right click** toggles the master switch: all strips on/off at once.
- **Scroll up** turns all strips on; **scroll down** turns them off. The
  wheel is absolute, so it does not toggle when you keep scrolling the same
  way.
- Master changes made from the bar icon are written through the same
  `shell.json` path as the panel controls, so per-edge settings persist.

## 0.5.0 — Further footprint reduction

- The settings popup is now **lazy**: the screen cube, sliders and switches
  only exist while the panel is open. A closed panel costs nothing beyond
  the bar button.
- Strip windows render with no child items — the window clear color is the
  strip itself, so a transparent strip has an empty scene graph.
- Slider drags and number-field typing are **debounced**: rapid changes
  coalesce into a single `shell.json` write per 250 ms burst instead of one
  write per tick.

## 0.4.1 — Memory optimization

- Strips are now created lazily: each edge is wrapped in a `Loader`, so a
  disabled edge creates **no window at all**. Previously all four
  `PanelWindow`s were instantiated up front and only hidden (`visible:
  false`) — each hidden window still owns a Wayland surface, scene graph
  and EGL buffer. With all edges off, the plugin now allocates zero strip
  windows; with one edge on, exactly one.
- Removed the idle `ColorAnimation` on strip windows (color changes only
  happen on a settings toggle, which no longer needs a running animation
  driver per window).

## 0.4.0 — Omarchy 4.x compatibility

- Dual-host support: works on Omarchy 4.x and older releases.
- On 4.x, settings are read from the injected `settings` property (inline on
  the `bar.layout` entry) and written via `shell.updateEntryInline`.
- On older hosts, settings are read from the top-level `syaifulmain.emptygap`
  key in shell.json and written via `shell.mutateShellConfig`; the strips are
  rendered by the `service` entry point (`Shim.qml`), which stays inert on 4.x.
- Added `barWidget.defaults` to the manifest.

## 0.3.0

- Per-edge config map (`edges.top/right/bottom/left`) with legacy migration.
