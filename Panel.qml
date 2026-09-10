import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Ui
import qs.Commons

// Bar button + popup panel for the Empty Gap plugin (Omarchy 4.x plugin API).
// Minimal UI:
//
//   - A screen "cube" preview: the four outer sides are clickable and act
//     as the per-edge enable toggles. The cube is the only selection control;
//     there is no separate enable switch.
//   - Four identical configuration rows (top / right / bottom / left), each
//     with: height slider, height number input, transparency toggle.
//   - The empty strips themselves are rendered by the Variants below; the
//     plugin no longer ships a separate service entry point because third-
//     party services receive no settings and cannot read shell config.
//
// Settings are inline on this widget's shell.json entry
// (bar.layout entry { "id": "syaifulmain.emptygap", ... }) and are read from
// the host-injected `settings` property. Writes go through
// bar.shell.updateEntryInline(moduleName, settings), which replaces the
// plugin's own entry — the only mutation the scoped facade allows.
//
// Settings schema (per-edge, v2):
//   {
//     "enabled": true,                  // master switch for all strips
//     "edges": {
//       "top":    { "enabled": true, "height": 26, "transparent": true },
//       "right": { ... }, "bottom": { ... }, "left": { ... }
//     }
//   }
// Legacy single-edge fields (`edge`, `height`, `transparent`) are migrated
// on read so pre-2.0 entry settings keep working.
Panel {
  id: root
  moduleName: "syaifulmain.emptygap"
  ipcTarget: "syaifulmain.emptygap"

  // ---- config helpers -------------------------------------------------
  // Dual-host support:
  //   - Omarchy 4.x injects inline entry settings via the `settings` property
  //     (or leaves it empty when the entry has no settings yet).
  //   - Older hosts expose the whole shell config through
  //     `bar.shell.shellConfig` with this plugin's settings under a top-level
  //     key. If neither surface has values, defaults apply.
  readonly property var legacyConfig: bar && bar.shell && bar.shell.shellConfig
    && bar.shell.shellConfig[moduleName] ? bar.shell.shellConfig[moduleName] : ({})
  readonly property bool hasInlineSettings: typeof root.settings !== "undefined"
    && root.settings && Object.keys(root.settings).length > 0
  readonly property var shimConfig: hasInlineSettings ? settings : legacyConfig

  readonly property var edgeNames: ["top", "right", "bottom", "left"]
  readonly property bool masterEnabled: shimConfig.enabled !== false
  readonly property var edges: normalizeEdges(shimConfig.edges, shimConfig)

  function normalizeEdges(rawEdges, legacyConfig) {
    var out = {}
    for (var i = 0; i < edgeNames.length; i++) {
      var name = edgeNames[i]
      var e = (rawEdges && rawEdges[name]) ? rawEdges[name] : {}
      out[name] = {
        "enabled": e.enabled === true,
        "height": clampHeight(e.height !== undefined ? e.height : 40),
        "transparent": e.transparent === true
      }
    }
    // One-time legacy migration: single-edge config -> per-edge map.
    var le = legacyConfig ? String(legacyConfig.edge || "") : ""
    if (edgeNames.indexOf(le) !== -1) {
      var legacyTarget = rawEdges && rawEdges[le] ? rawEdges[le] : null
      if (!legacyTarget || legacyTarget.enabled === undefined) {
        out[le].enabled = true
        if (legacyConfig.height !== undefined) out[le].height = clampHeight(legacyConfig.height)
        if (legacyConfig.transparent !== undefined) out[le].transparent = legacyConfig.transparent === true
      }
    }
    return out
  }

  function clampHeight(v) {
    var h = parseInt(v, 10)
    if (isNaN(h)) h = 40
    return Math.min(400, Math.max(0, h))
  }

  function edgeLabel(name) {
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  // Snapshot of the current settings as a plain entry object.
  function currentSettings() {
    var out = { "enabled": masterEnabled, "edges": {} }
    for (var i = 0; i < edgeNames.length; i++) {
      var name = edgeNames[i]
      out.edges[name] = {
        "enabled": edges[name].enabled,
        "height": edges[name].height,
        "transparent": edges[name].transparent
      }
    }
    return out
  }

  function persist(mutator) {
    if (!bar || !bar.shell) return
    var next = currentSettings()
    mutator(next)
    // Omarchy 4.x: replace this plugin's own bar-layout entry. Older hosts:
    // write the top-level <moduleName> key through the shell mutator.
    if (typeof bar.shell.updateEntryInline === "function") {
      bar.shell.updateEntryInline(moduleName, next)
    } else if (typeof bar.shell.mutateShellConfig === "function") {
      bar.shell.mutateShellConfig(function(config) {
        config[moduleName] = next
      })
    }
  }

  function persistEdge(name, mutator) {
    persist(function(c) {
      if (!c.edges || !c.edges[name]) {
        if (!c.edges) c.edges = {}
        c.edges[name] = { "enabled": false, "height": 40, "transparent": false }
      }
      mutator(c.edges[name])
    })
  }

  // ---------- bar button ----------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font glyph: a rectangle with a top bar, reads as "top strip".
    text: root.masterEnabled ? "󱢊" : "󱢋"
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
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(620))

    ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
      id: panelColumn
      width: scrollArea.availableWidth
      spacing: Style.space(12)

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
            text: "Reserves damaged screen edges"
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

      // ---------- screen cube: clickable outer sides = per-edge enable ----
      Item {
        id: screenCube
        width: parent.width
        implicitHeight: Style.space(140)

        // screen body (dim frame)
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.color: root.bar.foreground
          border.width: 1
          opacity: 0.3
          radius: Style.space(4)
        }

        Repeater {
          model: [
            { name: "top",    horizontal: true },
            { name: "bottom", horizontal: true },
            { name: "left",   horizontal: false },
            { name: "right",  horizontal: false }
          ]

          delegate: Rectangle {
            required property var modelData
            readonly property string edgeName: modelData.name
            readonly property bool enabledEdge: root.edges[edgeName] ? root.edges[edgeName].enabled : false
            readonly property int thickness: Style.space(12)
            readonly property int inset: modelData.horizontal ? 0 : Style.space(14)

            anchors.top: edgeName !== "bottom" ? parent.top : undefined
            anchors.bottom: edgeName !== "top" ? parent.bottom : undefined
            anchors.left: edgeName !== "right" ? parent.left : undefined
            anchors.right: edgeName !== "left" ? parent.right : undefined
            anchors.topMargin: inset
            anchors.bottomMargin: inset
            height: modelData.horizontal ? thickness : undefined
            width: modelData.horizontal ? undefined : thickness
            radius: Style.space(2)

            // enabled -> filled accent; disabled -> normal outline
            color: enabledEdge ? Color.accent : "transparent"
            border.color: enabledEdge ? Color.accent : root.bar.foreground
            border.width: 1
            opacity: enabledEdge ? 1.0 : 0.5
            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on opacity { ColorAnimation { duration: 180 } }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var name = edgeName
                root.persistEdge(name, function(e) { e.enabled = !root.edges[name].enabled })
              }
            }
          }
        }

        // Master on/off switch in the middle of the cube.
        Item {
          anchors.centerIn: parent
          width: masterSwitch.trackWidth
          height: masterSwitch.trackHeight

          ToggleSwitch {
            id: masterSwitch
            anchors.centerIn: parent
            checked: root.masterEnabled
            foreground: root.bar.foreground
            accent: Color.accent
            onToggled: function() {
              root.persist(function(c) { c.enabled = !root.masterEnabled })
            }
          }

          PanelToolTip {
            visible: masterSwitch.containsMouse
            text: root.masterEnabled ? "Disable all strips" : "Enable Empty Gap"
          }
        }
      }

      PanelSeparator {
        foreground: root.bar.foreground
      }

      // ---------- 4x edge configuration rows ------------------------------
      Repeater {
        model: root.edgeNames

        delegate: Column {
          required property string modelData
          readonly property string edgeName: modelData
          readonly property var edgeConfig: root.edges[edgeName] || { "enabled": false, "height": 40, "transparent": false }

          width: parent.width
          spacing: Style.space(6)

          Text {
            text: root.edgeLabel(edgeName)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            opacity: edgeConfig.enabled ? 1.0 : 0.5
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(14)

            // Slider track, themed like the audio panel.
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(28)
              opacity: edgeConfig.enabled ? 1.0 : 0.4
              enabled: edgeConfig.enabled

              PanelSlider {
                id: heightSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                bar: root.bar
                minimum: 0
                maximum: 200
                step: 2
                integer: true
                value: edgeConfig.height
                onMoved: function(v) {
                  if (v !== edgeConfig.height) {
                    root.persistEdge(edgeName, function(e) { e.height = v })
                  }
                }
                onReleased: function(v) {
                  if (v !== edgeConfig.height) {
                    root.persistEdge(edgeName, function(e) { e.height = v })
                  }
                }

                // Track outside edits (e.g. manual shell.json edits).
                Binding {
                  target: heightSlider
                  property: "value"
                  value: edgeConfig.height
                  when: !heightSlider.dragging
                }
              }
            }

            NumberField {
              fieldWidth: Style.space(64)
              value: edgeConfig.height
              from: 0
              to: 400
              stepSize: 2
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              Layout.preferredWidth: Style.space(64)
              Layout.alignment: Qt.AlignVCenter
              enabled: edgeConfig.enabled
              onModified: function(v) {
                if (v !== edgeConfig.height) {
                  root.persistEdge(edgeName, function(e) { e.height = v })
                }
              }
            }

            // Transparency switch (bare ToggleSwitch, not a full row).
            Item {
              Layout.leftMargin: Style.space(10)
              Layout.preferredWidth: transparencySwitch.trackWidth + Style.space(14)
              Layout.preferredHeight: Style.space(28)
              Layout.alignment: Qt.AlignVCenter
              opacity: edgeConfig.enabled ? 1.0 : 0.4
              enabled: edgeConfig.enabled

              ToggleSwitch {
                id: transparencySwitch
                anchors.centerIn: parent
                checked: edgeConfig.transparent
                foreground: root.bar.foreground
                accent: Color.accent
                onToggled: function() {
                  var name = edgeName
                  root.persistEdge(name, function(e) { e.transparent = !root.edges[name].transparent })
                }
              }

              // Hover tooltip hint for the bare switch.
              PanelToolTip {
                visible: transparencySwitch.containsMouse
                text: "Transparent strip"
              }
            }
          }
        }
      }
      }
    }
  }

  // ---------- empty strips ---------------------------------------------
  // Only rendered on Omarchy 4.x hosts (detected via the scoped facade's
  // updateEntryInline). Pre-4.x hosts render the strips from Shim.qml, so
  // creating them here too would stack two exclusive zones per edge.
  readonly property bool newHost: bar && bar.shell
    && typeof bar.shell.updateEntryInline === "function"

  Loader {
    active: root.newHost
    sourceComponent: stripVariants
  }

  Component {
    id: stripVariants

    Variants {
      model: ["top", "right", "bottom", "left"]

      delegate: Component {
      PanelWindow {
      required property string modelData
      readonly property string edgeName: modelData
      readonly property var edgeConfig: root.edges[edgeName] || {}
      readonly property bool active: root.masterEnabled && edgeConfig.enabled === true
      readonly property int stripHeight: edgeConfig.height !== undefined ? edgeConfig.height : 40
      readonly property bool horizontalEdge: edgeName === "top" || edgeName === "bottom"

      visible: active
      // Anchor the strip's edge plus both perpendicular ends so it stretches
      // full length while keeping `stripHeight` thickness.
      anchors.top: edgeName !== "bottom"
      anchors.bottom: edgeName !== "top"
      anchors.left: edgeName !== "right"
      anchors.right: edgeName !== "left"

      implicitHeight: horizontalEdge ? stripHeight : 0
      implicitWidth: horizontalEdge ? 0 : stripHeight
      exclusiveZone: active ? stripHeight : -stripHeight
      color: "transparent"
      surfaceFormat.opaque: false
      WlrLayershell.namespace: "syaifulmain-emptygap"
      WlrLayershell.layer: WlrLayer.Bottom

      Rectangle {
        anchors.fill: parent
        color: edgeConfig.transparent === true ? "transparent" : Color.bar.background
        Behavior on color {
          ColorAnimation {
            duration: 420
            easing.type: Easing.InOutQuad
          }
        }
      }
    }
    }
    }
  }
}
