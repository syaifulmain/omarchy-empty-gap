import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar button + popup panel for the screen shim. The button opens a panel
// with: shim edge (top/right/bottom/left), height, transparency toggle, and
// shim visibility toggle. Settings
// persist to shell.json under `syaifulmain.emptygap` via shell.mutateShellConfig, and
// Shim.qml (the service entry point) renders the strip from the same config.
Panel {
  id: root
  moduleName: "syaifulmain.emptygap"
  ipcTarget: "syaifulmain.emptygap"

  // ---- config helpers -------------------------------------------------
  readonly property var shimConfig: bar && bar.shell && bar.shell.shellConfig && bar.shell.shellConfig["syaifulmain.emptygap"]
    ? bar.shell.shellConfig["syaifulmain.emptygap"] : ({})

  readonly property bool shimVisible: shimConfig.enabled !== false
  readonly property bool shimTransparent: shimConfig.transparent === true
  readonly property string shimEdge: normalizeEdge(shimConfig.edge)
  readonly property int shimHeight: clampHeight(shimConfig.height)

  function normalizeEdge(v) {
    var e = String(v || "")
    return ["top", "right", "bottom", "left"].indexOf(e) !== -1 ? e : "top"
  }

  function persist(mutator) {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config["syaifulmain.emptygap"])) config["syaifulmain.emptygap"] = {}
      mutator(config["syaifulmain.emptygap"])
    })
  }

  function clampHeight(v) {
    var h = parseInt(v, 10)
    if (isNaN(h)) h = 40
    return Math.min(400, Math.max(0, h))
  }

  // ---------- bar button ----------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font glyph: a rectangle with a top bar, reads as "top strip".
    text: root.shimVisible ? "󱢊" : "󱢋"
    tooltipText: "Empty Gap"
    onPressed: function(b) { root.toggle() }
  }

  // ---------- popup panel ----------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
      id: panelColumn
      width: scrollArea.availableWidth
      spacing: Style.space(14)

      // ---------- header ----------
      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

        Text {
          id: heroIcon
          textFormat: Text.PlainText
          text: "󱢊"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.display
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "Empty Gap"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            text: "Reserves a damaged screen edge"
            color: root.bar.foreground
            opacity: 0.65
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator {
        foreground: root.bar.foreground
      }

      // ---------- visibility toggle ----------
      Toggle {
        width: parent.width
        label: "Shim enabled"
        description: root.shimVisible ? "Strip is reserving screen space" : "Strip is off"
        checked: root.shimVisible
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: function() { root.persist(function(c) { c.enabled = !root.shimVisible }) }
      }

      PanelSeparator {
        foreground: root.bar.foreground
      }

      // ---------- edge picker ----------
      Column {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "Edge"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Dropdown {
          width: parent.width
          value: root.shimEdge
          options: [
            { value: "top", label: "Top" },
            { value: "right", label: "Right" },
            { value: "bottom", label: "Bottom" },
            { value: "left", label: "Left" }
          ]
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onChanged: function(v) {
            if (v !== root.shimEdge) {
              root.persist(function(c) { c.edge = v })
            }
          }
        }
      }

      PanelSeparator {
        foreground: root.bar.foreground
      }

      // ---------- transparency toggle ----------
      Toggle {
        width: parent.width
        label: "Transparent"
        description: root.shimTransparent ? "Strip is see-through" : "Strip uses the theme background"
        checked: root.shimTransparent
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: function() { root.persist(function(c) { c.transparent = !root.shimTransparent }) }
      }

      PanelSeparator {
        foreground: root.bar.foreground
      }

      // ---------- height ----------
      Column {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "Height (px)"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(12)

          Slider {
            id: heightSlider
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(28)
            from: 0
            to: 200
            stepSize: 2
            value: root.shimHeight
            onMoved: {
              if (value !== root.shimHeight) {
                root.persist(function(c) { c.height = Math.round(value) })
              }
            }

            // Track outside edits (e.g. manual shell.json edits).
            Binding {
              target: heightSlider
              property: "value"
              value: root.shimHeight
              when: !heightSlider.pressed
            }
          }

          NumberField {
            label: "px"
            value: root.shimHeight
            from: 0
            to: 400
            stepSize: 2
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            Layout.preferredWidth: Style.space(110)
            onModified: function(v) {
              if (v !== root.shimHeight) {
                root.persist(function(c) { c.height = v })
              }
            }
          }
        }

        Text {
          text: "Drag the slider or type an exact height."
          color: root.bar.foreground
          opacity: 0.55
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          width: parent.width
        }
      }
      }
    }
  }
}
