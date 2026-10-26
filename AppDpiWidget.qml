import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "phenome.app-scaling"
  ipcTarget: "phenome.app-scaling"
  manageIpc: false

  property string filterText: ""
  property var allApps: []
  property var filteredApps: []
  property int selectedIndex: 0
  readonly property var selectedApp: filteredApps.length > 0 && selectedIndex >= 0 && selectedIndex < filteredApps.length
    ? filteredApps[selectedIndex]
    : null
  property real targetScale: selectedApp ? selectedApp.currentScale : 1.0
  property string statusMessage: ""
  property bool isError: false
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color selectedBackground: Commons.Color.menu.selectedBackground
  readonly property color selectedText: Commons.Color.menu.selectedText

  readonly property string glyphScale: String.fromCodePoint(0xF0747)
  readonly property string glyphRefresh: String.fromCodePoint(0xF0450)
  readonly property string glyphSearch: String.fromCodePoint(0xF0349)

  readonly property int customizedCount: {
    var count = 0;
    for (var i = 0; i < allApps.length; i++) {
      if (allApps[i].currentScale !== 1.0) count++;
    }
    return count;
  }

  readonly property string heroMeta: customizedCount > 0
    ? customizedCount + " CUSTOMIZED · " + allApps.length + " APPS"
    : allApps.length + " APPS INSTALLED"

  onSelectedAppChanged: {
    if (selectedApp) {
      targetScale = selectedApp.currentScale;
      statusMessage = "";
    }
  }

  onOpenedChanged: {
    if (opened) {
      statusMessage = "";
      isError = false;
      loadApps();
      Qt.callLater(function() {
        if (filterInput) filterInput.forceActiveFocus();
      });
    }
  }

  function loadApps() {
    if (!listProc.running) {
      listProc.running = true;
    }
  }

  function onAppsLoaded(raw) {
    try {
      var parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        root.allApps = parsed;
        var previousAppId = root.selectedApp ? root.selectedApp.id : "";
        var previousStatus = root.statusMessage;
        root.applyFilter();
        if (root.selectedApp && root.selectedApp.id === previousAppId) {
          root.statusMessage = previousStatus;
        }
      }
    } catch (e) {
      console.warn("AppDpi: failed to parse apps list JSON:", e);
    }
  }

  function applyFilter() {
    var term = root.filterText.trim().toLowerCase();
    var list = [];
    for (var i = 0; i < root.allApps.length; i++) {
      var app = root.allApps[i];
      if (!term) {
        list.push(app);
      } else {
        var name = (app.name || "").toLowerCase();
        var id = (app.id || "").toLowerCase();
        if (name.indexOf(term) !== -1 || id.indexOf(term) !== -1) {
          list.push(app);
        }
      }
    }
    root.filteredApps = list;
    if (root.filteredApps.length === 0) {
      root.selectedIndex = 0;
    } else if (root.selectedIndex >= root.filteredApps.length) {
      root.selectedIndex = root.filteredApps.length - 1;
    } else if (root.selectedIndex < 0) {
      root.selectedIndex = 0;
    }
    if (root.selectedApp) {
      root.targetScale = root.selectedApp.currentScale;
    }
  }

  function setScale(scale) {
    if (!root.selectedApp || actionProc.running) return;
    root.statusMessage = "Saving launcher scale...";
    root.isError = false;
    var target = Math.round(scale * 100) / 100;
    actionProc.command = ["omarchy-app-scaling", "set", root.selectedApp.id, target.toFixed(2), "--json"];
    actionProc.running = true;
  }

  function resetScale() {
    if (!root.selectedApp || actionProc.running) return;
    root.statusMessage = "Restoring defaults...";
    root.isError = false;
    actionProc.command = ["omarchy-app-scaling", "reset", root.selectedApp.id, "--json"];
    actionProc.running = true;
  }

  function adjustTargetScale(delta) {
    var next = Math.round((root.targetScale + delta) * 100) / 100;
    if (next < 0.50) next = 0.50;
    if (next > 3.00) next = 3.00;
    root.targetScale = next;
  }

  function resolveIcon(icon) {
    var value = String(icon || "");
    if (!value) return Quickshell.iconPath("application-x-executable", true);
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value;
    if (value.charAt(0) === "/") return Util.fileUrl(value);
    var themed = Quickshell.iconPath(value, true);
    if (themed) return themed;
    return Quickshell.iconPath("application-x-executable", true);
  }

  function tintColor(baseColor, alpha) {
    return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, alpha);
  }

  Process {
    id: listProc
    command: ["omarchy-app-scaling", "list", "--json"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onAppsLoaded(text);
      }
    }
  }

  Process {
    id: actionProc
    command: []
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text);
          if (res.success) {
            root.statusMessage = "Launcher scale saved. Fully quit (including tray), then relaunch through the desktop launcher. Direct shortcuts may bypass this.";
            root.isError = false;
            root.loadApps();
          } else {
            root.statusMessage = res.error || "Failed to update scaling.";
            root.isError = true;
          }
        } catch (e) {
          root.statusMessage = "Operation finished.";
          root.loadApps();
        }
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function status(): string { return root.heroMeta }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "App Scaling (" + (root.customizedCount > 0 ? root.customizedCount + " customized" : "per-app DPI") + ")"
    iconComponent: Component {
      Item {
        width: 16
        height: 16
        readonly property color col: button.active && button.useActiveColor ? button.activeColor : button.foreground

        // Corner scale brackets
        // Top-Left
        Rectangle { x: 0; y: 0; width: 4; height: 2; color: parent.col }
        Rectangle { x: 0; y: 0; width: 2; height: 4; color: parent.col }

        // Top-Right
        Rectangle { x: 12; y: 0; width: 4; height: 2; color: parent.col }
        Rectangle { x: 14; y: 0; width: 2; height: 4; color: parent.col }

        // Bottom-Left
        Rectangle { x: 0; y: 14; width: 4; height: 2; color: parent.col }
        Rectangle { x: 0; y: 12; width: 2; height: 4; color: parent.col }

        // Bottom-Right
        Rectangle { x: 12; y: 14; width: 4; height: 2; color: parent.col }
        Rectangle { x: 14; y: 12; width: 2; height: 4; color: parent.col }

        // Center solid square dot
        Rectangle {
          x: 6
          y: 6
          width: 4
          height: 4
          color: parent.col
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.loadApps();
      else root.toggle();
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: filterInput
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: mainColumn
        width: parent.width
        spacing: Style.space(12)

        // Hero Header
        PanelHero {
          id: hero
          width: parent.width
          title: "App Scaling"
          meta: root.heroMeta
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Item {
              width: Style.space(26)
              height: Style.space(26)
              readonly property color col: root.accent

              // Corner brackets
              Rectangle { x: 0; y: 0; width: Style.space(7); height: Style.space(2); color: parent.col }
              Rectangle { x: 0; y: 0; width: Style.space(2); height: Style.space(7); color: parent.col }

              Rectangle { anchors.right: parent.right; y: 0; width: Style.space(7); height: Style.space(2); color: parent.col }
              Rectangle { anchors.right: parent.right; y: 0; width: Style.space(2); height: Style.space(7); color: parent.col }

              Rectangle { x: 0; anchors.bottom: parent.bottom; width: Style.space(7); height: Style.space(2); color: parent.col }
              Rectangle { x: 0; anchors.bottom: parent.bottom; width: Style.space(2); height: Style.space(7); color: parent.col }

              Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: Style.space(7); height: Style.space(2); color: parent.col }
              Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: Style.space(2); height: Style.space(7); color: parent.col }

              // Center solid square dot
              Rectangle {
                anchors.centerIn: parent
                width: Style.space(8)
                height: Style.space(8)
                color: parent.col
              }
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: root.glyphRefresh
              tooltipText: "Refresh Applications"
              foreground: hero.foreground
              fontFamily: hero.fontFamily
              enabled: !listProc.running
              opacity: listProc.running ? 0.5 : 1.0
              onClicked: root.loadApps()
            }
          }
        }

        // Search Input Box
        Rectangle {
          width: parent.width
          height: Style.space(36)
          radius: Style.cornerRadius
          color: root.tintColor(root.foreground, 0.08)
          border.color: filterInput.activeFocus ? root.accent : root.tintColor(root.foreground, 0.15)
          border.width: 1

          Item {
            anchors.fill: parent

            Text {
              id: searchGlyph
              textFormat: Text.PlainText
              text: root.glyphSearch
              color: root.foreground
              font.pixelSize: Style.font.body
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              opacity: 0.6
            }

            Item {
              id: clearButton
              visible: root.filterText.length > 0
              width: Style.space(24)
              height: Style.space(24)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                textFormat: Text.PlainText
                text: "✕"
                color: clearMouse.containsMouse ? root.foreground : root.tintColor(root.foreground, 0.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.centerIn: parent
              }

              MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.filterText = "";
                  root.applyFilter();
                  filterInput.forceActiveFocus();
                }
              }
            }

            TextInput {
              id: filterInput
              anchors.left: searchGlyph.right
              anchors.leftMargin: Style.space(8)
              anchors.right: clearButton.visible ? clearButton.left : parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              clip: true
              selectByMouse: true

              Text {
                textFormat: Text.PlainText
                text: "Filter applications..."
                color: root.foreground
                opacity: 0.4
                visible: !filterInput.text && !filterInput.activeFocus
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }

              onTextChanged: {
                if (root.filterText !== text) {
                  root.filterText = text;
                  root.applyFilter();
                }
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  if (root.filterText) {
                    root.filterText = "";
                    root.applyFilter();
                  } else {
                    root.close();
                  }
                  event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                  if (root.selectedIndex < root.filteredApps.length - 1) {
                    root.selectedIndex++;
                    appsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                  }
                  event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                  if (root.selectedIndex > 0) {
                    root.selectedIndex--;
                    appsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                  }
                  event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                  root.adjustTargetScale(-0.05);
                  event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                  root.adjustTargetScale(0.05);
                  event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.setScale(root.targetScale);
                  event.accepted = true;
                }
              }
            }
          }
        }
        // Section Header
        PanelSectionHeader {
          text: "APPLICATIONS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // Applications List (height ~160)
        Rectangle {
          width: parent.width
          height: Math.max(0, Style.space(160) - Math.max(0, selectedAppCard.height - selectedAppCard.implicitHeight))
          radius: Style.cornerRadius
          color: root.tintColor(root.foreground, 0.04)
          border.color: root.tintColor(root.foreground, 0.10)
          border.width: 1

          ListView {
            id: appsList
            anchors.fill: parent
            anchors.margins: Style.space(4)
            clip: true
            model: root.filteredApps
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds

            Text {
              textFormat: Text.PlainText
              visible: root.filteredApps.length === 0
              anchors.centerIn: parent
              text: listProc.running ? "Loading applications..." : "No matching applications"
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            delegate: Rectangle {
              id: appRow
              width: appsList.width
              height: Style.space(38)
              radius: Style.space(6)
              readonly property bool isSelected: index === root.selectedIndex
              color: isSelected
                ? root.selectedBackground
                : rowMouse.containsMouse
                  ? root.tintColor(root.foreground, 0.08)
                  : "transparent"

              Item {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)

                Image {
                  id: appIcon
                  width: Style.space(22)
                  height: Style.space(22)
                  source: root.resolveIcon(modelData.icon)
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                }

                Row {
                  id: trailingBadges
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  // Toolkit badge
                  Rectangle {
                    height: Style.space(18)
                    width: toolkitBadgeText.implicitWidth + Style.space(8)
                    radius: Style.space(3)
                    color: root.tintColor(root.foreground, 0.12)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      id: toolkitBadgeText
                      textFormat: Text.PlainText
                      text: modelData.toolkit === "unrecognized" || modelData.toolkit === "unknown" ? "UNRECOGNIZED" : modelData.toolkit.toUpperCase()
                      color: appRow.isSelected ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.centerIn: parent
                      opacity: 0.8
                    }
                  }

                  // Scale pill
                  Rectangle {
                    width: Math.max(Style.space(46), scalePillText.implicitWidth + Style.space(10))
                    height: Style.space(18)
                    radius: Style.space(9)
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.currentScale !== 1.0
                      ? root.accent
                      : root.tintColor(root.foreground, 0.10)

                    Text {
                      id: scalePillText
                      textFormat: Text.PlainText
                      text: modelData.currentScale.toFixed(2) + "x"
                      color: modelData.currentScale !== 1.0
                        ? Commons.Color.background
                        : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      anchors.centerIn: parent
                    }
                  }
                }

                Column {
                  anchors.left: appIcon.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: trailingBadges.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0
                  clip: true

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: appRow.isSelected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: appRow.isSelected
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.id
                    color: appRow.isSelected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    opacity: 0.5
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedIndex = index;
                  if (filterInput) filterInput.forceActiveFocus();
                }
              }
            }
          }
        }

        // Selected App Card & Controls
        Rectangle {
          id: selectedAppCard
          width: parent.width
          implicitHeight: !selectedApp ? Style.space(50) : (selectedApp.toolkit === "webapp" ? Style.space(170) : (selectedApp.toolkit === "game" ? Style.space(140) : (selectedApp.toolkit === "unrecognized" || selectedApp.toolkit === "unknown" ? Style.space(255) : Style.space(190))))
          height: root.selectedApp ? Math.max(implicitHeight, selectedAppContent.implicitHeight + Style.space(20)) : implicitHeight
          radius: Style.cornerRadius
          color: root.tintColor(root.foreground, 0.05)
          border.color: root.tintColor(root.foreground, 0.10)
          border.width: 1

          Item {
            anchors.fill: parent
            visible: !root.selectedApp
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "Select an application above to configure scaling"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: selectedAppContent
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(8)
            visible: root.selectedApp !== null

            // App title & strategy row
            Row {
              width: parent.width
              spacing: Style.space(8)

              Image {
                width: Style.space(28)
                height: Style.space(28)
                source: root.selectedApp ? root.resolveIcon(root.selectedApp.icon) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(38)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                  textFormat: Text.PlainText
                  text: root.selectedApp ? root.selectedApp.name : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                }

                Row {
                  spacing: Style.space(6)
                  Text {
                    textFormat: Text.PlainText
                    text: root.selectedApp ? root.selectedApp.toolkit.toUpperCase() + " · " + root.selectedApp.strategy : ""
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }
            // WebApp guidance notice
            Rectangle {
              width: parent.width
              height: Style.space(98)
              radius: Style.cornerRadius
              color: root.tintColor(root.accent, 0.08)
              border.color: root.tintColor(root.accent, 0.25)
              border.width: 1
              visible: root.selectedApp.toolkit === "webapp"

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: "🌐 WebApp (Browser-managed zoom)"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: "WebApps share your browser session. In the application window, use:"
                  color: root.foreground
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  width: parent.width
                }

                Row {
                  spacing: Style.space(12)
                  Text {
                    textFormat: Text.PlainText
                    text: "Zoom In: Ctrl +"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: "Zoom Out: Ctrl -"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: "Reset: Ctrl 0"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }

            // Game guidance notice
            Rectangle {
              width: parent.width
              height: Style.space(68)
              radius: Style.cornerRadius
              color: root.tintColor(root.foreground, 0.05)
              border.color: root.tintColor(root.foreground, 0.15)
              border.width: 1
              visible: root.selectedApp.toolkit === "game"

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  text: "🎮 3D Game"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: "Games manage resolution and UI scaling in their in-game graphics settings."
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                  width: parent.width
                }
              }
            }

            // Unrecognized engine notice
            Rectangle {
              width: parent.width
              height: Style.space(56)
              radius: Style.cornerRadius
              color: root.tintColor(root.foreground, 0.05)
              border.color: root.tintColor(root.foreground, 0.12)
              border.width: 1
              visible: root.selectedApp.toolkit === "unrecognized" || root.selectedApp.toolkit === "unknown"

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  text: "⚠️ Unrecognized engine"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: "Applying scale injects markers for every supported engine (Qt, GTK, Slint), but with no guarantees."
                  color: root.foreground
                  opacity: 0.75
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  width: parent.width
                }
              }
            }

            // Manageable App Controls (Stepper, Presets, Action buttons)
            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: root.selectedApp.toolkit !== "webapp" && root.selectedApp.toolkit !== "game"

              // Stepper Row
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(16)

                Button {
                  text: "−0.05"
                  width: Style.space(68)
                  height: Style.space(30)
                  fontSize: Style.font.bodySmall
                  onClicked: root.adjustTargetScale(-0.05)
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.targetScale.toFixed(2) + "x"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                  text: "+0.05"
                  width: Style.space(68)
                  height: Style.space(30)
                  fontSize: Style.font.bodySmall
                  onClicked: root.adjustTargetScale(0.05)
                }
              }

              // Presets Row
              Row {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: [0.75, 0.85, 1.00, 1.15, 1.25]
                  delegate: Button {
                    text: modelData.toFixed(2) + "x"
                    width: Math.floor((parent.width - Style.space(24)) / 5)
                    height: Style.space(26)
                    horizontalPadding: Style.space(4)
                    fontSize: Style.font.caption
                    selected: Math.abs(root.targetScale - modelData) < 0.01
                    onClicked: {
                      root.targetScale = modelData;
                    }
                  }
                }
              }

              // Action Buttons Row
              Row {
                width: parent.width
                spacing: Style.space(8)

                Button {
                  text: root.selectedApp.toolkit === "unrecognized" || root.selectedApp.toolkit === "unknown" ? "Apply (No Guarantees)" : "Apply Scale"
                  width: (parent.width - Style.space(8)) * 0.6
                  height: Style.space(32)
                  bordered: true
                  selected: true
                  fontSize: Style.font.bodySmall
                  onClicked: root.setScale(root.targetScale)
                }

                Button {
                  text: "Reset"
                  width: (parent.width - Style.space(8)) * 0.4
                  height: Style.space(32)
                  bordered: true
                  fontSize: Style.font.bodySmall
                  onClicked: root.resetScale()
                }
              }

              // Status feedback
              Text {
                textFormat: Text.PlainText
                visible: root.statusMessage !== ""
                text: root.statusMessage
                color: root.isError ? root.urgent : root.foreground
                opacity: root.isError ? 1.0 : 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
                width: parent.width
              }
            }
          }
        }

        // Footer hint line
        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "enter apply  ·  esc close  ·  r refresh"
          color: root.tintColor(root.foreground, 0.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
