import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.services

// The tray (StatusNotifierItem): left click activates the app (or opens its menu when that is all it
// has) · right click: its menu, drawn like the rest of the shell · middle: its secondary action.
// blueman's icon stays out while the bar shows Bluetooth itself (bar/BluetoothSeg.qml).
Item {
    id: tray

    property var bar: null
    readonly property bool compact: bar ? bar.compact : false
    readonly property bool ownBluetooth: !!bar && BarLayout.members("group/status", bar.variant).includes("bluetooth")
    readonly property var items: SystemTray.items.values.filter(i => !(ownBluetooth && i.id === "blueman"))
    property bool shown: items.length > 0

    implicitWidth: row.implicitWidth + (compact ? 6 : 8)
    implicitHeight: Theme.barHeight
    visible: shown

    Row {
        id: row
        x: tray.compact ? 3 : 4
        height: parent.height
        spacing: 0

        Repeater {
            model: tray.items

            delegate: Item {
                id: slot
                required property var modelData
                readonly property int iconSize: tray.compact ? 15 : 16
                width: iconSize + (tray.compact ? 12 : 14)
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 4
                    anchors.bottomMargin: 4
                    radius: Theme.innerRadius
                    color: Theme.hover
                    opacity: mouse.containsMouse ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: slot.iconSize
                    source: slot.modelData.icon
                    opacity: slot.modelData.status === Status.Passive ? 0.5 : 1
                }

                // asks for attention: a dot in the second accent
                Rectangle {
                    visible: slot.modelData.status === Status.NeedsAttention
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                    x: parent.width / 2 + slot.iconSize / 2 - 4
                    y: parent.height / 2 - slot.iconSize / 2 - 2
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    property real wheelRest: 0

                    function openMenu() {
                        if (slot.modelData.hasMenu)
                            tray.bar.togglePopup(slot, menuPopup, "tray:" + slot.modelData.id, { menu: slot.modelData.menu });
                    }

                    onClicked: e => {
                        tray.bar.hideTip(slot);
                        if (e.button === Qt.RightButton)
                            openMenu();
                        else if (e.button === Qt.MiddleButton)
                            slot.modelData.secondaryActivate();
                        else if (slot.modelData.onlyMenu)
                            openMenu();
                        else
                            slot.modelData.activate();
                    }
                    onWheel: w => {
                        wheelRest += w.angleDelta.y;
                        if (Math.abs(wheelRest) >= 120) {
                            slot.modelData.scroll(Math.trunc(wheelRest / 120), false);
                            wheelRest = 0;
                        }
                    }
                    onContainsMouseChanged: {
                        const m = slot.modelData;
                        const title = m.tooltipTitle || m.title || m.id;
                        if (containsMouse && title)
                            tray.bar.showTip(slot, () => Apps.esc(title)
                                + (m.tooltipDescription ? `<br><font color='${Theme.dim}'>${m.tooltipDescription}</font>` : ""));
                        else
                            tray.bar.hideTip(slot);
                    }
                }
            }
        }
    }

    Component {
        id: menuPopup
        TrayMenu {}
    }
}
