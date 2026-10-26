import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
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

  onSelectedAppChanged: {
    if (selectedApp) {
      targetScale = selectedApp.currentScale;
      statusMessage = "";
    }
  }

  // Shares the [menu] tokens
  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color border: Commons.Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property color scrim: Commons.Color.menu.scrim
  readonly property color selectedBackground: Commons.Color.menu.selectedBackground
  readonly property color selectedText: Commons.Color.menu.selectedText
  readonly property color accent: Commons.Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int contentSpacing: Style.spacing.md

  readonly property int cardWidth: Math.min(Style.space(860), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true;
    root.filterText = "";
    root.statusMessage = "";
    root.isError = false;
    root.loadApps();
    Qt.callLater(function() {
      if (searchInput) searchInput.forceActiveFocus();
    });
  }

  function close() {
    root.opened = false;
  }

  function dismiss() {
    root.opened = false;
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "phenome.app-dpi");
    }
  }

  function toggle() {
    if (root.opened) root.dismiss();
    else root.open("{}");
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
        root.applyFilter();
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
    root.statusMessage = "Applying scale...";
    root.isError = false;
    var target = Math.round(scale * 100) / 100;
    actionProc.command = ["omarchy-app-dpi", "set", root.selectedApp.id, target.toFixed(2), "--json"];
    actionProc.running = true;
  }

  function resetScale() {
    if (!root.selectedApp || actionProc.running) return;
    root.statusMessage = "Restoring defaults...";
    root.isError = false;
    actionProc.command = ["omarchy-app-dpi", "reset", root.selectedApp.id, "--json"];
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

  Process {
    id: listProc
    command: ["omarchy-app-dpi", "list", "--json"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.onAppsLoaded(value);
      }
    }
  }

  Process {
    id: actionProc
    command: []
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var res = JSON.parse(value);
          if (res.success) {
            root.statusMessage = "Configuration saved. Restart application to apply.";
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

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-app-dpi"

    Rectangle {
      anchors.fill: parent
      color: root.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(12)

        // Top Header
        Row {
          width: parent.width
          height: Style.space(42)
          spacing: Style.space(12)

          // Title
          Text {
            textFormat: Text.PlainText
            text: "App Scaling"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          // Search Field
          Rectangle {
            id: searchBox
            width: parent.width - Style.space(180)
            height: Style.space(38)
            radius: root.cornerRadius
            color: Style.tintFor(root.foreground, 0.08)
            border.color: searchInput.activeFocus ? root.accent : Style.tintFor(root.foreground, 0.15)
            border.width: 1
            anchors.verticalCenter: parent.verticalCenter

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "🔍"
                color: root.foreground
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
                opacity: 0.6
              }

              TextInput {
                id: searchInput
                width: parent.width - Style.space(32)
                text: root.filterText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                selectByMouse: true

                Text {
                  textFormat: Text.PlainText
                  text: "Search installed applications..."
                  color: root.foreground
                  opacity: 0.4
                  visible: !searchInput.text && !searchInput.activeFocus
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
                      root.dismiss();
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

          // Close button
          Button {
            id: closeButton
            text: "✕"
            width: Style.space(36)
            height: Style.space(36)
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.dismiss()
          }
        }

        // Horizontal Separator
        Rectangle {
          width: parent.width
          height: 1
          color: Style.tintFor(root.foreground, 0.12)
        }

        // Two-Column Content Area
        Row {
          width: parent.width
          height: parent.height - Style.space(60)
          spacing: Style.space(16)

          // Left Pane: Application List
          Item {
            width: Math.floor(parent.width * 0.48)
            height: parent.height

            ListView {
              id: appsList
              anchors.fill: parent
              clip: true
              model: root.filteredApps
              spacing: Style.space(4)
              boundsBehavior: Flickable.StopAtBounds

              Text {
                textFormat: Text.PlainText
                visible: root.filteredApps.length === 0
                anchors.centerIn: parent
                text: listProc.running ? "Loading applications..." : "No matching applications"
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              delegate: Rectangle {
                id: appRow
                width: appsList.width
                height: Style.space(52)
                radius: root.cornerRadius
                readonly property bool isSelected: index === root.selectedIndex
                color: isSelected ? root.selectedBackground : rowMouse.containsMouse ? Style.tintFor(root.foreground, 0.05) : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(12)

                  Image {
                    width: Style.space(32)
                    height: Style.space(32)
                    source: root.resolveIcon(modelData.icon)
                    anchors.verticalCenter: parent.verticalCenter
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                  }

                  Column {
                    width: parent.width - Style.space(110)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.name
                      color: appRow.isSelected ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: appRow.isSelected
                      elide: Text.ElideRight
                      width: parent.width
                    }

                    Row {
                      spacing: Style.space(6)

                      // Toolkit badge
                      Rectangle {
                        height: Style.space(16)
                        width: toolkitLabel.implicitWidth + Style.space(8)
                        radius: Style.space(4)
                        color: Style.tintFor(root.foreground, 0.12)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                          id: toolkitLabel
                          textFormat: Text.PlainText
                          text: modelData.toolkit.toUpperCase()
                          color: appRow.isSelected ? root.selectedText : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          anchors.centerIn: parent
                          opacity: 0.8
                        }
                      }

                      Text {
                        textFormat: Text.PlainText
                        text: modelData.id
                        color: appRow.isSelected ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        opacity: 0.5
                        elide: Text.ElideRight
                        width: parent.parent.width - toolkitLabel.implicitWidth - Style.space(20)
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }
                  }

                  // Scale pill
                  Rectangle {
                    width: Style.space(50)
                    height: Style.space(24)
                    radius: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.currentScale !== 1.0 || modelData.isOverridden
                      ? root.accent
                      : Style.tintFor(root.foreground, 0.10)

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.currentScale.toFixed(2) + "x"
                      color: modelData.currentScale !== 1.0 || modelData.isOverridden
                        ? Commons.Color.background
                        : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      anchors.centerIn: parent
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
                    if (searchInput) searchInput.forceActiveFocus();
                  }
                }
              }
            }
          }

          // Vertical Separator
          Rectangle {
            width: 1
            height: parent.height
            color: Style.tintFor(root.foreground, 0.12)
          }

          // Right Pane: Detail & Scaling Controls
          Item {
            width: parent.width - Math.floor(parent.width * 0.48) - Style.space(17)
            height: parent.height

            Column {
              anchors.fill: parent
              spacing: Style.space(16)
              visible: root.selectedApp !== null

              // App Header Info
              Row {
                width: parent.width
                spacing: Style.space(12)

                Image {
                  width: Style.space(48)
                  height: Style.space(48)
                  source: root.selectedApp ? root.resolveIcon(root.selectedApp.icon) : ""
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: parent.width - Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    textFormat: Text.PlainText
                    text: root.selectedApp ? root.selectedApp.name : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: root.selectedApp ? root.selectedApp.id : ""
                    color: root.foreground
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }
              }

              // Toolkit & Strategy Meta Card
              Rectangle {
                width: parent.width
                height: Style.space(56)
                radius: root.cornerRadius
                color: Style.tintFor(root.foreground, 0.05)
                border.color: Style.tintFor(root.foreground, 0.10)
                border.width: 1

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(2)

                  Row {
                    spacing: Style.space(6)
                    Text {
                      textFormat: Text.PlainText
                      text: "Detected Toolkit:"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      opacity: 0.6
                    }
                    Text {
                      textFormat: Text.PlainText
                      text: root.selectedApp ? root.selectedApp.toolkit.toUpperCase() : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Row {
                    spacing: Style.space(6)
                    Text {
                      textFormat: Text.PlainText
                      text: "Strategy:"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      opacity: 0.6
                    }
                    Text {
                      textFormat: Text.PlainText
                      text: root.selectedApp ? root.selectedApp.strategy : ""
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }
              }

              // Scaling Controls Section
              Column {
                width: parent.width
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  text: "Target Scale Factor"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                // Stepper Row
                Row {
                  spacing: Style.space(12)
                  anchors.horizontalCenter: parent.horizontalCenter

                  Button {
                    text: "− 0.05"
                    width: Style.space(70)
                    height: Style.space(38)
                    onClicked: root.adjustTargetScale(-0.05)
                  }

                  Rectangle {
                    width: Style.space(100)
                    height: Style.space(38)
                    radius: root.cornerRadius
                    color: Style.tintFor(root.foreground, 0.08)
                    border.color: root.accent
                    border.width: 1

                    Text {
                      textFormat: Text.PlainText
                      text: root.targetScale.toFixed(2) + "x"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      anchors.centerIn: parent
                    }
                  }

                  Button {
                    text: "+ 0.05"
                    width: Style.space(70)
                    height: Style.space(38)
                    onClicked: root.adjustTargetScale(0.05)
                  }
                }

                // Presets Row
                Row {
                  spacing: Style.space(6)
                  anchors.horizontalCenter: parent.horizontalCenter

                  Repeater {
                    model: [0.75, 0.80, 0.85, 1.00, 1.15, 1.25, 1.50]
                    delegate: Button {
                      text: modelData.toFixed(2) + "x"
                      height: Style.space(28)
                      selected: Math.abs(root.targetScale - modelData) < 0.01
                      onClicked: {
                        root.targetScale = modelData;
                      }
                    }
                  }
                }
              }

              // Action Buttons Row
              Row {
                width: parent.width
                spacing: Style.space(10)

                Button {
                  text: "Apply Scale"
                  width: (parent.width - Style.space(10)) * 0.6
                  height: Style.space(40)
                  bordered: true
                  selected: true
                  onClicked: root.setScale(root.targetScale)
                }

                Button {
                  text: "Reset Default"
                  width: (parent.width - Style.space(10)) * 0.4
                  height: Style.space(40)
                  bordered: true
                  onClicked: root.resetScale()
                }
              }

              // Status / Feedback message
              Text {
                textFormat: Text.PlainText
                visible: root.statusMessage !== ""
                text: root.statusMessage
                color: root.isError ? Commons.Color.urgent : root.foreground
                opacity: root.isError ? 1.0 : 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
                width: parent.width
              }
            }

            // Placeholder when nothing selected
            Item {
              anchors.fill: parent
              visible: root.selectedApp === null

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "Select an application to manage scaling"
                color: root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }
      }
    }
  }
}
