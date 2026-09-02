# Changelog

## 1.2.0

- Rename to **Empty Gap** (`saep.topshim` → `saep.emptygap`).
- Strip can be placed on any edge: top, right, bottom, left (edge selector in panel).
- Strip now claims the screen edge *before* the Omarchy bar (`WlrLayer.Bottom`),
  so a same-edge bar stays visible inside/below the strip instead of being pushed out.
- Panel: scrollable content, larger height slider, numeric height input (0–400 px).

## 1.1.0

- Edge selector (initial multi-edge support).

## 1.0.0

- Initial release: top strip with height, transparency, and visibility controls.
