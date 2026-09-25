# Changelog

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
