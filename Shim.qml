import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Empty strip that reserves a damaged area of the screen. Sits on one edge
// (top / right / bottom / left, default top). State lives in shell.json under
// `syaifulmain.emptygap` via the syaifulmain.emptygap bar-widget panel and is read here
// through the injected `shell.shellConfig`. Independent of the main bar's
// own transparency and visibility settings.
Item {
  id: root

  // Injected by the omarchy-shell host service loader.
  property var shell: null

  readonly property var config: shell && shell.shellConfig && shell.shellConfig["syaifulmain.emptygap"]
    ? shell.shellConfig["syaifulmain.emptygap"]
    : ({})

  readonly property bool shimVisible: config.enabled !== false
  readonly property bool shimTransparent: config.transparent === true
  readonly property string shimEdge: ["top", "right", "bottom", "left"].indexOf(String(config.edge)) !== -1
    ? String(config.edge) : "top"
  readonly property bool horizontalEdge: shimEdge === "top" || shimEdge === "bottom"
  // Shared normalization rule with Panel.qml: honor the documented 0-400
  // range, including 0 (strip present but reserves no space). Invalid values
  // fall back to the 40px default.
  readonly property int shimHeight: {
    var h = parseInt(config.height, 10)
    return (h >= 0 && h <= 400) ? h : 40
  }

  PanelWindow {
    visible: root.shimVisible
    // Anchor the strip's edge plus both perpendicular ends so it stretches
    // full length while keeping `shimHeight` thickness.
    anchors.top: root.shimEdge !== "bottom"
    anchors.bottom: root.shimEdge !== "top"
    anchors.left: root.shimEdge !== "right"
    anchors.right: root.shimEdge !== "left"

    implicitHeight: root.horizontalEdge ? root.shimHeight : 0
    implicitWidth: root.horizontalEdge ? 0 : root.shimHeight
    exclusiveZone: root.shimVisible ? root.shimHeight : -root.shimHeight
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "syaifulmain-emptygap"
    WlrLayershell.layer: WlrLayer.Bottom

    Rectangle {
      anchors.fill: parent
      color: root.shimTransparent ? "transparent" : Color.bar.background
      Behavior on color {
        ColorAnimation {
          duration: 420
          easing.type: Easing.InOutQuad
        }
      }
    }
  }
}
