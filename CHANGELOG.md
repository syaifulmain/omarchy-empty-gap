# Changelog

## 1.4.0 — Omarchy 4.x compatibility

- Dual-host support: works on Omarchy 4.x and older releases.
- On 4.x, settings are read from the injected `settings` property (inline on
  the `bar.layout` entry) and written via `shell.updateEntryInline`.
- On older hosts, settings are read from the top-level `syaifulmain.emptygap`
  key in shell.json and written via `shell.mutateShellConfig`; the strips are
  rendered by the `service` entry point (`Shim.qml`), which stays inert on 4.x.
- Added `barWidget.defaults` to the manifest.

## 1.3.0

- Per-edge config map (`edges.top/right/bottom/left`) with legacy migration.
