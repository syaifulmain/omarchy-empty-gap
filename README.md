# Empty Gap

[![Omarchy](https://img.shields.io/badge/Omarchy-shell%20plugin-blueviolet)](https://omarchy.org)
[![Version](https://img.shields.io/badge/version-1.2.0-green)]()

An [Omarchy](https://omarchy.org) shell plugin (Quickshell) that displays an **empty strip** along a screen edge to reserve a damaged monitor area — e.g. the dark strip at the top of a laptop with a cracked screen.

![Preview](preview.png)

## Features

- **Four edges**: place the strip on the **Top / Right / Bottom / Left** screen edge.
- **Any height**: 0–400 px, via a slider or exact numeric input in the panel.
- **Transparent**: use the bar theme color or go fully transparent.
- **On/off**: hide or show the strip anytime without reloading the shell.
- **Original bar stays visible**: if the Omarchy bar sits on the same edge as the strip, the bar is pushed inward (to the inner side of the strip) instead of being covered by it.
- **Independent**: the strip does not follow `omarchy toggle bar` or the original bar's transparency toggle.
- **Live reload**: every change is saved to `shell.json` and applied immediately.

## Installation

```bash
omarchy plugin add https://github.com/syaifulmain/omarchy-empty-gap.git --enable
```

During the interactive install, pick the bar section for the button (default: *right*).

Once installed, the 󱢊 icon button appears on the bar. Click it to open the settings panel.

## Usage

The **Empty Gap** button panel contains:

| Control | Function |
| --- | --- |
| Edge | Strip position: Top / Right / Bottom / Left |
| Shim enabled | Show/hide the strip |
| Transparent | Transparent strip or theme background |
| Height | Strip height (slider 0–200, numeric input 0–400 px; 0 = strip present but reserves no space) |

All values are stored in `~/.config/omarchy/shell.json`:

```json
"syaifulmain.emptygap": { "edge": "top", "enabled": true, "height": 40, "transparent": false }
```

## How it works

The strip is a layer-shell `PanelWindow` on `WlrLayer.Bottom` with the namespace
`syaifulmain-emptygap`. Because the compositor processes the bottom layer first, the
strip claims the outermost screen edge (exclusive zone) and the Omarchy bar on
the same edge is automatically pushed inward — to the inner side of the strip.

## Verify installation

```bash
omarchy plugin list            # syaifulmain.emptygap should appear
hyprctl layers | grep emptygap # strip is active
```

## Structure

```
manifest.json   # plugin metadata (id: syaifulmain.emptygap, kinds: service + bar-widget)
Shim.qml        # service: PanelWindow strip on a screen edge
Panel.qml       # bar-widget: button + scrollable settings panel
```

## License

[MIT](LICENSE)
