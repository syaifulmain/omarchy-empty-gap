import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Empty strips that reserve damaged areas of the screen, one per screen edge
// (top / right / bottom / left). State lives in shell.json under
// `syaifulmain.emptygap` via the syaifulmain.emptygap bar-widget panel and is read here
// through the injected `shell.shellConfig`. Independent of the main bar's
// own transparency and visibility settings.
//
// Config schema (per-edge, v2):
//   {
//     "enabled": true,                  // master switch for all strips
//     "edges": {
//       "top":    { "enabled": true, "height": 26, "transparent": true },
//       "right":  { ... }, "bottom": { ... }, "left": { ... }
//     }
//   }
// Legacy single-edge fields (`edge`, `height`, `transparent`, plus legacy
// `enabled`) are migrated on read so old shell.json keeps working.
Item {
  id: root

  // Injected by the omarchy-shell host service loader.
  property var shell: null

  readonly property var config: shell && shell.shellConfig && shell.shellConfig["syaifulmain.emptygap"]
    ? shell.shellConfig["syaifulmain.emptygap"]
    : ({})

  readonly property bool masterEnabled: config.enabled !== false
  readonly property var edges: normalizeEdges(config.edges, config)

  // Shared normalization rule with Panel.qml: honor the documented 0-400
  // range, including 0 (strip present but reserves no space). Invalid values
  // fall back to the 40px default.
  function clampHeight(v) {
    var h = parseInt(v, 10)
    if (isNaN(h)) h = 40
    return Math.min(400, Math.max(0, h))
  }

  function normalizeEdgeMap(raw, legacyEdge, legacyHeight, legacyTransparent) {
    var out = {}
    var names = ["top", "right", "bottom", "left"]
    for (var i = 0; i < names.length; i++) {
      var name = names[i]
      var e = (raw && raw[name]) ? raw[name] : {}
      out[name] = {
        "enabled": e.enabled === true,
        "height": clampHeight(e.height !== undefined ? e.height : 40),
        "transparent": e.transparent === true
      }
    }
    // One-time legacy migration: single-edge config -> per-edge map.
    if (names.indexOf(String(legacyEdge)) !== -1 && !(raw && raw[String(legacyEdge)] && raw[String(legacyEdge)].enabled !== undefined)) {
      out[String(legacyEdge)].enabled = true
      if (legacyHeight !== undefined) out[String(legacyEdge)].height = clampHeight(legacyHeight)
      if (legacyTransparent !== undefined) out[String(legacyEdge)].transparent = legacyTransparent === true
    }
    return out
  }

  function normalizeEdges(rawEdges, legacyConfig) {
    return normalizeEdgeMap(
      rawEdges,
      legacyConfig ? legacyConfig.edge : undefined,
      legacyConfig ? legacyConfig.height : undefined,
      legacyConfig ? legacyConfig.transparent : undefined
    )
  }

  readonly property bool anyActive: masterEnabled && (edges.top.enabled || edges.right.enabled || edges.bottom.enabled || edges.left.enabled)

  // Only active on pre-4.x hosts, which expose the full shell config through
  // the injected `shell`. On Omarchy 4.x the bar widget (Panel.qml) renders
  // the strips itself and this service stays unloaded.
  readonly property bool legacyHost: shell && shell.shellConfig !== undefined

  Loader {
    active: root.legacyHost && root.anyActive
    sourceComponent: legacyStrips
  }

  Component {
    id: legacyStrips

    Repeater {
      model: ["top", "right", "bottom", "left"]

      // One Loader per edge: a disabled edge creates no window at all.
      // A hidden (visible: false) PanelWindow still owns a Wayland surface,
      // scene graph and EGL buffer, so instantiating all four up front
      // wastes memory for an idle plugin.
      delegate: Loader {
        id: edgeLoader
        required property string modelData
        readonly property string edgeName: modelData
        readonly property var edgeConfig: root.edges[edgeName] || {}
        active: root.masterEnabled && edgeConfig.enabled === true

        sourceComponent: Component {
          PanelWindow {
            readonly property string edgeName: edgeLoader.edgeName
            readonly property var edgeConfig: edgeLoader.edgeConfig
            readonly property bool horizontalEdge: edgeName === "top" || edgeName === "bottom"
            readonly property int stripHeight: edgeConfig.height !== undefined ? edgeConfig.height : 40

            // Anchor the strip's edge plus both perpendicular ends so it stretches
            // full length while keeping `stripHeight` thickness.
            anchors.top: edgeName !== "bottom"
            anchors.bottom: edgeName !== "top"
            anchors.left: edgeName !== "right"
            anchors.right: edgeName !== "left"

            implicitHeight: horizontalEdge ? stripHeight : 0
            implicitWidth: horizontalEdge ? 0 : stripHeight
            exclusiveZone: stripHeight
            // The window clear color IS the strip — no child items needed,
            // so a transparent strip renders an empty scene graph.
            color: edgeConfig.transparent === true ? "transparent" : Color.bar.background
            surfaceFormat.opaque: false
            WlrLayershell.namespace: "syaifulmain-emptygap"
            WlrLayershell.layer: WlrLayer.Bottom
          }
        }
      }
    }
  }
}
