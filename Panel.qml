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
//   - A top diamond of five gap buttons — Top / Left / master / Right /
//     Bottom — drawn in the same 3x3 shape as the screen edges they toggle.
//     The centre button reads the master state (On / Off) and enables or
//     disables every strip at once.
//   - Four identical configuration rows (top / right / bottom / left), each
//     with: height slider, height number input, transparency toggle. All four
//     rows are always listed, so an edge can be configured before enabling it.
//   - One cursor shared by keyboard and mouse (the kit's hasCursor
//     convention): hover or the arrow keys move it, and exactly one control
//     is highlighted at a time.
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

  // Master writes (bar-button right click / mouse wheel) share this path:
  // every state change goes through the same shell.json writer, so the
  // config entry stays the single source of truth. Re-persisting the current
  // state is idempotent — same JSON, no error.
  function setMasterEnabled(value) {
    persist(function(c) { c.enabled = value === true })
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

  // Debounced persistence for high-frequency edits (slider drags, number
  // typing): rapid changes coalesce into one shell.json write per burst
  // instead of one write per tick.
  property var _pendingHeights: ({})

  // ---------- typed height ------------------------------------------------
  // Digits typed while the cursor sits on a height input edit that strip
  // immediately — no Space first, no focus, no inline text editor. Digits are
  // buffered so "5" then "0" reads as 50, and the buffer restarts when the
  // cursor leaves the field, after a pause, or when Space is pressed.
  property string typedDigits: ""
  property int typedRow: -1
  property int typedCol: -1

  // ---------- cursor model ----------------------------------------------
  // ONE cursor shared by keyboard and mouse, exactly like the built-in audio
  // panel: hovering an item moves the cursor there, the arrow keys move it,
  // and every highlight derives from `hasCursor`/`current` — never from
  // `containsMouse`. That invariant is what keeps exactly one item lit, so
  // the popup always answers "where am I?" instead of outlining everything
  // the pointer has crossed.
  property string focusSection: "gaps"   // "gaps" (diamond) | "config" (rows)
  property int gapIndex: 0               // index into gapOrder
  property int rowIndex: 0               // index into edgeNames
  property int colIndex: 0               // 0 slider, 1 number field, 2 switch
  property bool editing: false           // slider edit mode: Left/Right adjust
  property string editControl: ""        // "slider" | ""
  // Revealed when the popup opens, so the first target (the Top gap) is
  // visibly highlighted before any keypress; hover and keys set it too.
  property bool cursorActive: false

  // Reading order of the diamond. The buttons are drawn as a 3x3 grid that
  // mirrors the screen — Top above, Bottom below, Left/Right beside the
  // center master toggle — so a name alone is not enough to place them.
  readonly property var gapOrder: ["top", "left", "all", "right", "bottom"]

  // Diamond adjacency by name; "" means stay put. Up/Down walk the vertical
  // axis, Left/Right step to the side buttons and back, so a keypress never
  // jumps somewhere the eye cannot follow.
  readonly property var gapNeighbors: ({
    top:    { "up": "",       "down": "all",    "left": "left", "right": "right" },
    left:   { "up": "top",    "down": "bottom", "left": "",     "right": "all" },
    all:    { "up": "top",    "down": "bottom", "left": "left", "right": "right" },
    right:  { "up": "top",    "down": "bottom", "left": "all",  "right": "" },
    bottom: { "up": "all",    "down": "",       "left": "left", "right": "right" }
  })

  function gapIndexOf(name) {
    for (var i = 0; i < gapOrder.length; i++) if (gapOrder[i] === name) return i
    return 0
  }

  function currentGapName() {
    var name = gapOrder[gapIndex]
    return name !== undefined ? name : "top"
  }

  // Mouse entry points: move the one cursor, never paint straight from hover.
  function setGapCursor(index) {
    root.cursorActive = true
    root.focusSection = "gaps"
    root.gapIndex = index
    root.clearTypedHeight()
  }

  function setConfigCursor(row, col) {
    root.cursorActive = true
    root.focusSection = "config"
    root.rowIndex = row
    root.colIndex = col
    // A different control means a different number: the old buffer would
    // otherwise keep appending to the field it was started on.
    if (root.typedRow !== row || root.typedCol !== col) root.clearTypedHeight()
  }

  // ---------- typed height helpers ----------------------------------------
  function typedFieldActive(row, col) {
    return root.typedDigits !== "" && root.typedRow === row && root.typedCol === col
  }

  function clearTypedHeight() {
    root.typedDigits = ""
    root.typedRow = -1
    root.typedCol = -1
    if (typedResetTimer) typedResetTimer.stop()
  }

  // Space on the input keeps the cursor there but starts a fresh number, so
  // the next digit replaces the value instead of appending to it.
  function restartTypedHeight() {
    root.clearTypedHeight()
    root.typedRow = root.rowIndex
    root.typedCol = 1
  }

  function applyTypedHeight() {
    if (root.typedDigits === "") return
    var row = root.typedRow
    if (row < 0 || row >= root.edgeNames.length) return
    var edge = root.edgeNames[row]
    var next = root.clampHeight(parseInt(root.typedDigits, 10))
    if (next !== root.edges[edge].height) {
      root.queueHeight(edge, next)
      root.flushPendingHeights()
    }
  }

  // PanelKeyCatcher forwards every printable key here. Digits edit the height
  // under the cursor directly; Backspace takes the last digit back.
  function handleTextKey(t) {
    if (root.focusSection !== "config" || root.colIndex !== 1) return
    if (root.rowIndex >= root.edgeNames.length) return
    var isDigit = t.length === 1 && t >= "0" && t <= "9"
    var isBackspace = t === "\b" || t === "\u007f"
    if (!isDigit && !isBackspace) return

    if (root.typedRow !== root.rowIndex || root.typedCol !== root.colIndex) {
      root.typedDigits = ""
      root.typedRow = root.rowIndex
      root.typedCol = root.colIndex
    }
    if (isBackspace) {
      if (root.typedDigits === "") return
      root.typedDigits = root.typedDigits.substring(0, root.typedDigits.length - 1)
    } else {
      var candidate = root.typedDigits + t
      // Keep the documented 0-400 range valid while typing.
      if (parseInt(candidate, 10) > 400) return
      root.typedDigits = candidate
    }
    if (root.typedDigits === "") return
    typedResetTimer.restart()
    root.applyTypedHeight()
  }

  // Keyboard moves must keep their target on screen: on a short display j/k
  // would otherwise walk the cursor out of the scroll viewport.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var margin = 6
    var maxY = Math.max(0, (flick.contentHeight || 0) - flick.height)
    if (maxY <= Style.space(24)) { flick.contentY = 0; return }
    var point = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = point.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    if (top < viewTop + margin) flick.contentY = Math.max(0, Math.min(maxY, top - margin))
    else if (bottom > viewBottom - margin)
      flick.contentY = Math.max(0, Math.min(maxY, bottom + margin - flick.height))
  }

  // Status line: names the current cursor target and the keys that act on it,
  // so the highlight's position is never a guess.
  readonly property string cursorTitle: {
    if (root.focusSection === "gaps") {
      var gap = root.currentGapName()
      if (gap === "all") return root.masterEnabled ? "All gaps · on" : "All gaps · off"
      return root.edgeLabel(gap) + " gap"
    }
    var edge = root.edgeNames[root.rowIndex]
    if (edge === undefined) return ""
    var head = root.edgeLabel(edge) + " · "
    if (root.editing && root.editControl === "slider")
      return head + "height " + root.edges[edge].height + " px"
    if (root.colIndex === 0) return head + "height slider"
    if (root.colIndex === 1) {
      if (root.typedFieldActive(root.rowIndex, 1)) return head + "height " + root.typedDigits + " px"
      return head + "height value"
    }
    return head + "transparency"
  }

  readonly property string cursorHint: {
    if (root.editing && root.editControl === "slider") return "← → adjust · ↑ ↓ leave"
    if (root.focusSection === "gaps") return "← → ↑ ↓ move · space toggle"
    if (root.colIndex === 0) return "space to drag · ← → next control"
    if (root.colIndex === 1) return "type a number (0-400)"
    return "space toggles"
  }

  function resetFocusState() {
    root.focusSection = "gaps"
    root.gapIndex = 0          // the Top gap button
    root.rowIndex = 0
    root.colIndex = 0
    root.editing = false
    root.editControl = ""
    root.clearTypedHeight()
    root.cursorActive = true
    if (scrollArea && scrollArea.contentItem && scrollArea.contentItem.contentY !== undefined)
      scrollArea.contentItem.contentY = 0
  }

  function exitEdit() {
    root.editing = false
    root.editControl = ""
  }

  function handleMove(dx, dy) {
    if (root.editing) {
      if (root.editControl === "slider") {
        if (dy !== 0) { root.exitEdit(); root.moveConfig(dy, 0); return }
        if (dx !== 0) { root.adjustCurrentHeight(dx * 2); return }
      }
      return
    }
    root.cursorActive = true
    if (root.focusSection === "gaps") root.moveGap(dx, dy)
    else root.moveConfig(dy, dx)
  }

  function moveGap(dx, dy) {
    var name = root.currentGapName()
    root.clearTypedHeight()
    if (dy === 1 && name === "bottom") {
      // The configuration list sits directly below the diamond, so dropping
      // off the Bottom button enters its first row.
      root.focusSection = "config"
      root.rowIndex = 0
      root.colIndex = 0
      return
    }
    var dir = dx === 1 ? "right" : (dx === -1 ? "left" : (dy === 1 ? "down" : "up"))
    var next = root.gapNeighbors[name][dir]
    if (next) root.gapIndex = root.gapIndexOf(next)
  }

  function moveConfig(dy, dx) {
    root.clearTypedHeight()
    if (dx !== 0) root.colIndex = Math.max(0, Math.min(2, root.colIndex + dx))
    if (dy === 0) return
    if (dy === -1 && root.rowIndex === 0) {
      // Leaving the first row upward lands on the gap button for the same
      // edge, so a row and its button stay visibly paired.
      root.focusSection = "gaps"
      root.gapIndex = root.gapIndexOf(root.edgeNames[root.rowIndex])
      return
    }
    root.rowIndex = Math.max(0, Math.min(root.edgeNames.length - 1, root.rowIndex + dy))
  }

  function handleActivate() {
    if (root.editing) { root.exitEdit(); return }
    root.cursorActive = true
    if (root.focusSection === "gaps") {
      var gap = root.currentGapName()
      if (gap === "all") root.persist(function(c) { c.enabled = !root.masterEnabled })
      else root.persistEdge(gap, function(e) { e.enabled = !root.edges[gap].enabled })
      return
    }
    if (root.rowIndex >= root.edgeNames.length) return
    var edge = root.edgeNames[root.rowIndex]
    if (root.colIndex === 0) {
      root.editing = true
      root.editControl = "slider"
    } else if (root.colIndex === 1) {
      // Digits already edit the height (see handleTextKey); Space only asks
      // for a fresh number so the next digit replaces instead of appending.
      root.restartTypedHeight()
    } else if (root.colIndex === 2) {
      root.persistEdge(edge, function(e) { e.transparent = !root.edges[edge].transparent })
    }
  }

  function adjustCurrentHeight(delta) {
    if (root.rowIndex >= root.edgeNames.length) return
    var edge = root.edgeNames[root.rowIndex]
    var cfg = root.edges[edge]
    if (!cfg) return
    var next = root.clampHeight(cfg.height + delta)
    if (next !== cfg.height) {
      root.queueHeight(edge, next)
      root.flushPendingHeights()
    }
  }

  function handleClose() {
    root.clearTypedHeight()
    if (root.editing) { root.exitEdit(); return }
    root.close()
  }

  function handleTab(direction) {
    if (root.editing) { root.exitEdit(); return }
    root.switchPanel(direction)
  }

  onOpenedChanged: { if (opened) root.resetFocusState() }

  Timer {
    id: heightFlushTimer
    interval: 250
    onTriggered: root.flushPendingHeights()
  }

  // A pause while typing only ends the current number (each digit already
  // applied itself); the next digit then starts a fresh one.
  Timer {
    id: typedResetTimer
    interval: 1500
    onTriggered: root.clearTypedHeight()
  }

  function queueHeight(name, value) {
    var next = {}
    for (var k in _pendingHeights) next[k] = _pendingHeights[k]
    next[name] = value
    _pendingHeights = next
    heightFlushTimer.restart()
  }

  function flushPendingHeights() {
    var names = Object.keys(_pendingHeights)
    if (!names.length) return
    for (var i = 0; i < names.length; i++) {
      var name = names[i]
      var value = _pendingHeights[name]
      if (value !== undefined && value !== edges[name].height) {
        persistEdge(name, (function(eName, h) {
          return function(e) { e.height = h }
        })(name, value))
      }
    }
    _pendingHeights = ({})
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
    // Left click opens the settings panel; right click toggles every strip
    // at once. Middle click is deliberately ignored.
    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        root.toggle()
      } else if (b === Qt.RightButton) {
        root.setMasterEnabled(!root.masterEnabled)
      }
    }
    // Wheel is absolute: up turns every strip on, down turns them off.
    onWheelMoved: function(delta) {
      if (delta > 0) root.setMasterEnabled(true)
      else if (delta < 0) root.setMasterEnabled(false)
    }
  }

  // ---------- popup panel ----------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(
      panelBody.active && panelBody.item ? panelBody.item.implicitHeight : Style.space(520),
      Style.space(660))

    // Standard keyboard plumbing: Tab / Shift+Tab hop to the next / previous
    // bar widget via switchPanel(), Escape closes — same behavior as the
    // clock, audio and ports panels. The cursor itself lives on the root (see
    // the cursor model above); this only turns keys into cursor moves.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.handleClose()
      onTabRequested: function(direction) { root.handleTab(direction) }
      onMoveRequested: function(dx, dy) { root.handleMove(dx, dy) }
      onActivateRequested: root.handleActivate()
      onTextKey: function(t) { root.handleTextKey(t) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelBody.active && panelBody.item
          && panelBody.item.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        // Lazy panel body: instantiated on open, destroyed on close.
        Loader {
          id: panelBody
          width: scrollArea.availableWidth
          active: root.opened || panel.visible
          sourceComponent: Component {
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

              // ---------- gap switches: 3x3 diamond ----------
              // Every button is its own hit target and its own cursor stop, so
              // hovering or arrowing onto one lights exactly that one.
              GridLayout {
                id: gapGrid
                width: parent.width
                columns: 3
                columnSpacing: Style.space(6)
                rowSpacing: Style.space(6)

                // Icon-only buttons: the arrow already says which screen edge
                // a button owns, and the status line under the rows spells the
                // name out when the cursor lands on one.
                GapButton {
                  Layout.row: 0; Layout.column: 1
                  gapKey: "top"; gapIndex: 0; iconText: "↑"
                }
                GapButton {
                  Layout.row: 1; Layout.column: 0
                  gapKey: "left"; gapIndex: 1; iconText: "←"
                }
                GapButton {
                  Layout.row: 1; Layout.column: 1
                  gapKey: "all"; gapIndex: 2
                  // The one button with a label: the master state is what the
                  // user needs to read at a glance, and On/Off says it
                  // unambiguously.
                  text: root.masterEnabled ? "On" : "Off"
                }
                GapButton {
                  Layout.row: 1; Layout.column: 2
                  gapKey: "right"; gapIndex: 3; iconText: "→"
                }
                GapButton {
                  Layout.row: 2; Layout.column: 1
                  gapKey: "bottom"; gapIndex: 4; iconText: "↓"
                }
              }

              PanelSeparator {
                foreground: root.bar.foreground
              }

              PanelSectionHeader {
                text: "GAP CONFIGURATION"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              // ---------- one configuration row per edge ----------
              // All four rows are always listed, not only the enabled edges,
              // so a strip can be sized and styled before it is switched on.
              Column {
                width: parent.width
                spacing: Style.space(10)

                Repeater {
                  model: root.edgeNames

                  delegate: Column {
                    id: configRow
                    // Both model values must be declared required: a delegate
                    // that declares any required property gets no context
                    // properties, so a bare `index` stays undefined and every
                    // row would resolve to index 0 — which made one hovered
                    // control light up every row at once.
                    required property int index
                    required property string modelData
                    readonly property string edgeName: modelData
                    readonly property int rowIdx: index
                    readonly property var edgeConfig: root.edges[edgeName]
                      || ({ "enabled": false, "height": 40, "transparent": false })
                    readonly property bool rowHasCursor: root.cursorActive
                      && root.focusSection === "config" && root.rowIndex === rowIdx

                    width: parent.width
                    spacing: Style.space(4)

                    // Header is just the edge name: the height is already in
                    // the number field and the off state reads from the dimmed
                    // label and the controls themselves.
                    Item {
                      width: parent.width
                      implicitHeight: rowLabel.implicitHeight

                      Text {
                        id: rowLabel
                        textFormat: Text.PlainText
                        text: root.edgeLabel(configRow.edgeName)
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.subtitle
                        // The header stays neutral: the accent cursor ring
                        // marks the exact control, never the whole row.
                        font.bold: false
                        opacity: configRow.edgeConfig.enabled ? 1.0 : 0.55
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    RowLayout {
                      width: parent.width
                      spacing: Style.space(12)

                      // Slider track. The highlight is drawn by the
                      // CursorSurface around the track — the number field and
                      // the switch carry their own — so only the control the
                      // cursor sits on lights up, never the whole row.
                      CursorSurface {
                        id: heightSurface
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.space(28)
                        hasCursor: configRow.rowHasCursor && root.colIndex === 0
                        onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(heightSurface)
                        foreground: root.bar.foreground
                        accent: Color.accent

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
                          value: configRow.edgeConfig.height
                          onMoved: function(v) {
                            if (v !== configRow.edgeConfig.height) root.queueHeight(configRow.edgeName, v)
                          }
                          onReleased: function(v) {
                            if (v !== configRow.edgeConfig.height) root.queueHeight(configRow.edgeName, v)
                            root.flushPendingHeights()
                          }

                          // Track outside edits (e.g. manual shell.json edits);
                          // hold off while a drag or debounced write is in flight.
                          Binding {
                            target: heightSlider
                            property: "value"
                            value: configRow.edgeConfig.height
                            when: !heightSlider.dragging && root._pendingHeights[configRow.edgeName] === undefined
                          }
                        }

                        HoverHandler {
                          onHoveredChanged: if (hovered) root.setConfigCursor(configRow.rowIdx, 0)
                        }

                        CursorRing {
                          active: configRow.rowHasCursor && root.colIndex === 0
                          baseRadius: Style.cornerRadius
                        }
                      }

                      // Wrapper owns the cursor ring: NumberField is a
                      // Column, and anchored children inside a positioner are
                      // not allowed.
                      Item {
                        Layout.preferredWidth: Style.space(64)
                        Layout.preferredHeight: heightField.implicitHeight
                        Layout.alignment: Qt.AlignVCenter

                        NumberField {
                          id: heightField
                          anchors.fill: parent
                          objectName: "heightField_" + configRow.edgeName
                          fieldWidth: Style.space(64)
                          value: configRow.edgeConfig.height
                          from: 0
                          to: 400
                          stepSize: 2
                          foreground: root.bar.foreground
                          fontFamily: root.bar.fontFamily
                          hasCursor: configRow.rowHasCursor && root.colIndex === 1
                          onHovered: function(on) {
                            if (on) root.setConfigCursor(configRow.rowIdx, 1)
                          }
                          // Digits are handled by the panel itself (see
                          // handleTextKey), so the box stays a read-only
                          // display plus mouse steppers: no inner text editor
                          // can swallow the keys or fight the saved value.
                          Binding {
                            target: heightField.field
                            property: "editable"
                            value: false
                          }
                          onModified: function(v) {
                            if (v !== configRow.edgeConfig.height) root.queueHeight(configRow.edgeName, v)
                          }
                        }

                        CursorRing {
                          active: configRow.rowHasCursor && root.colIndex === 1
                          baseRadius: Style.cornerRadius
                        }
                      }

                      ToggleSwitch {
                        id: transparencySwitch
                        Layout.leftMargin: Style.space(10)
                        Layout.alignment: Qt.AlignVCenter
                        checked: configRow.edgeConfig.transparent
                        hasCursor: configRow.rowHasCursor && root.colIndex === 2
                        foreground: root.bar.foreground
                        accent: Color.accent
                        onHovered: function(on) {
                          if (on) root.setConfigCursor(configRow.rowIdx, 2)
                        }
                        onToggled: {
                          var name = configRow.edgeName
                          root.persistEdge(name, function(e) { e.transparent = !root.edges[name].transparent })
                        }

                        PanelToolTip {
                          visible: transparencySwitch.containsMouse
                          text: "Transparent strip"
                        }

                        CursorRing {
                          active: configRow.rowHasCursor && root.colIndex === 2
                          baseRadius: Style.cornerRadius
                        }
                      }
                    }
                  }
                }
              }

              PanelSeparator {
                foreground: root.bar.foreground
              }

              // ---------- cursor status ----------
              Item {
                width: parent.width
                implicitHeight: Math.max(statusTitle.implicitHeight, statusHint.implicitHeight)

                Text {
                  id: statusTitle
                  textFormat: Text.PlainText
                  text: root.cursorTitle
                  color: Color.accent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                  width: Math.min(implicitWidth, parent.width * 0.55)
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: statusHint
                  textFormat: Text.PlainText
                  text: root.cursorHint
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width - statusTitle.width - Style.space(8)
                  horizontalAlignment: Text.AlignRight
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }
        }
      }
    }
  }

  // One gap switch in the top diamond: a plain kit Button whose only extra job
  // is mapping hover and the panel cursor onto the right index.
  component GapButton: Button {
    id: gapButton

    required property string gapKey
    required property int gapIndex

    readonly property bool gapOn: gapKey === "all"
      ? root.masterEnabled
      : (root.edges[gapKey] ? root.edges[gapKey].enabled : false)

    // Every button owns exactly one third of the diamond, and the minimum is
    // dropped so the layout cannot let content decide a column's width. The
    // layout distributes space proportionally to the preferred size, so without
    // this the labelled master button widened its whole column — and flipping
    // On (bold) to Off resized every button in the row.
    Layout.preferredWidth: Math.max(0, (gapGrid.width - gapGrid.columnSpacing * 2) / 3)
    Layout.minimumWidth: 0
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter

    tooltipText: gapKey === "all"
      ? (root.masterEnabled ? "Disable all strips" : "Enable all strips")
      : "Show / hide the " + gapKey + " strip"
    bordered: true
    selected: gapOn
    hasCursor: root.cursorActive && root.focusSection === "gaps" && root.gapIndex === gapIndex
    // Enabled strips keep an accent tint, so the on/off state stays readable
    // while the cursor ring moves independently of it.
    foreground: gapOn ? Color.accent : root.bar.foreground
    fontFamily: root.bar.fontFamily
    // Arrows and the On/Off label must measure exactly the same, or the
    // labelled button ends up a different height than its neighbours in the
    // same grid. One shared token (14 px at the default 12 px base) keeps the
    // whole diamond even and still follows the theme.
    readonly property int glyphSize: Style.font.title
    iconSize: glyphSize
    fontSize: glyphSize

    onHovered: function(on) { if (on) root.setGapCursor(gapIndex) }
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(gapButton)

    onClicked: {
      if (gapKey === "all") root.persist(function(c) { c.enabled = !root.masterEnabled })
      else root.persistEdge(gapKey, function(e) { e.enabled = !root.edges[gapKey].enabled })
    }

    CursorRing {
      active: gapButton.hasCursor
      baseRadius: gapButton.radius
    }
  }

  // Accent ring drawn around the one control the panel cursor sits on. The
  // kit's hover-cursor chrome is deliberately softer than its normal chrome in
  // some themes (a 0.25 border alpha against 0.4), which reads as "less" the
  // moment the cursor arrives; this ring is the unambiguous "you are here".
  // Disabled, so it never intercepts hover or clicks from the control below.
  component CursorRing: Rectangle {
    id: ring

    property bool active: false
    property real baseRadius: 0

    enabled: false
    // Flush with the control's own bounds rather than just outside them: the
    // panel ScrollView clips at its viewport edge, which cut the ring off on
    // the left/right-most controls (the Left/Right gap buttons and the
    // transparency switches). Staying inside the bounds cannot clip.
    anchors.fill: parent
    radius: ring.baseRadius
    color: ring.active ? Util.alpha(Color.accent, 0.12) : "transparent"
    border.color: Color.accent
    border.width: ring.active ? Math.max(2, Style.space(2)) : 0
    visible: ring.active
  }

  // ---------- keyboard shortcut ----------------------------------------
  // Deliberately NOT registered by the plugin. A shortcut is the user's to
  // own: registering one at runtime (hyprctl eval + hl.bind) spawns an
  // external process and, because it has to unbind the keys first, would
  // silently evict whatever the user already had on them. Add it in
  // ~/.config/hypr/bindings.lua instead (see README):
  //
  //   o.bind("SUPER + CTRL + G", "Empty Gap panel",
  //     "omarchy-shell shell toggle syaifulmain.emptygap")
  //
  // The toggle goes through the shell's panel IPC, which resolves the live
  // bar-widget instance per monitor.

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
