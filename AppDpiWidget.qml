import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "phenome.app-dpi"
  ipcTarget: "phenome.app-dpi"
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

  function tintColor(baseColor, alpha) {
    return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, alpha);
  }

  Process {
    id: listProc
    command: ["omarchy-app-dpi", "list", "--json"]
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
    text: root.glyphScale
    tooltipText: "App Scaling (" + (root.customizedCount > 0 ? root.customizedCount + " customized" : "per-app DPI") + ")"
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
            Text {
              textFormat: Text.PlainText
              text: root.glyphScale
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
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

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: root.glyphSearch
              color: root.foreground
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
              opacity: 0.6
            }

            TextInput {
              id: filterInput
              width: parent.width - Style.space(30)
              text: root.filterText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
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
          height: Style.space(160)
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

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Image {
                  width: Style.space(22)
                  height: Style.space(22)
                  source: root.resolveIcon(modelData.icon)
                  anchors.verticalCenter: parent.verticalCenter
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                }

                Column {
                  width: parent.width - Style.space(110)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0

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

                // Toolkit badge
                Rectangle {
                  height: Style.space(16)
                  width: toolkitBadgeText.implicitWidth + Style.space(6)
                  radius: Style.space(3)
                  color: root.tintColor(root.foreground, 0.12)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: toolkitBadgeText
                    textFormat: Text.PlainText
                    text: modelData.toolkit.toUpperCase()
                    color: appRow.isSelected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.centerIn: parent
                    opacity: 0.8
                  }
                }

                // Scale pill
                Rectangle {
                  width: Math.max(Style.space(48), scalePillText.implicitWidth + Style.space(12))
                  height: Style.space(20)
                  radius: Style.space(10)
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
          width: parent.width
          height: selectedApp ? Style.space(190) : Style.space(50)
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

            // Stepper & Presets
            // Stepper Row
            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "−0.05"
                width: Style.space(60)
                height: Style.space(28)
                fontSize: Style.font.caption
                onClicked: root.adjustTargetScale(-0.05)
              }

              Rectangle {
                width: Style.space(80)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.tintColor(root.foreground, 0.08)
                border.color: root.accent
                border.width: 1

                Text {
                  textFormat: Text.PlainText
                  text: root.targetScale.toFixed(2) + "x"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.centerIn: parent
                }
              }

              Button {
                text: "+0.05"
                width: Style.space(60)
                height: Style.space(28)
                fontSize: Style.font.caption
                onClicked: root.adjustTargetScale(0.05)
              }
            }

            // Presets Row
            Row {
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: [0.75, 0.80, 0.85, 1.00, 1.15, 1.25, 1.50]
                delegate: Button {
                  text: modelData.toFixed(2) + "x"
                  height: Style.space(26)
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
                text: "Apply Scale"
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
              elide: Text.ElideRight
              width: parent.width
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
