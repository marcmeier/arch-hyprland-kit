import QtQuick
import Quickshell.Hyprland
import qs.services

// Workspaces 1 to 5 and a "…" button for the rest, straight from Hyprland's IPC. The active one
// carries the accent gradient, which slides over when you switch; workspaces with windows get a
// thin accent ring, empty ones stay dim, urgent ones turn red. Click: go there · wheel: next/previous.
Pill {
    id: pill

    readonly property int last: 5
    readonly property var monitor: bar ? bar.monitor : null
    readonly property var activeWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace : Hyprland.focusedWorkspace
    readonly property int active: activeWs ? activeWs.id : 0
    // monitor.focused is not kept up to date by Quickshell: compare with the focused monitor instead
    readonly property bool focusedHere: !monitor || !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === monitor.name
    readonly property var all: Hyprland.workspaces.values

    function windows(id) {
        const w = all.find(w => w.id === id);
        return w ? w.toplevels.values.length : 0;
    }
    function urgent(id) {
        const w = all.find(w => w.id === id);
        return !!(w && (w.urgent || w.toplevels.values.some(t => t.urgent)));
    }
    readonly property var extra: all.filter(w => w.id > last && (w.toplevels.values.length > 0 || w.id === active))
                                    .map(w => w.id).sort((a, b) => a - b)

    padding: compact ? 3 : 4

    // after a reload of the shell Hyprland's state comes back with the next event: ask right away
    Component.onCompleted: {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
    }

    Item {
        id: box
        implicitWidth: buttons.implicitWidth
        implicitHeight: Theme.barHeight

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real rest: 0
            onWheel: event => {
                rest += event.angleDelta.y;
                if (Math.abs(rest) >= 120) {
                    Actions.focusWorkspace(rest > 0 ? "e-1" : "e+1");
                    rest = 0;
                }
            }
        }

        // the active workspace's gradient, behind the buttons
        Rectangle {
            id: indicator
            readonly property Item target: {
                if (pill.active > 0 && pill.active <= pill.last)
                    return rep.count >= pill.active ? rep.itemAt(pill.active - 1) : null;
                return pill.active > pill.last && more.visible ? more : null;
            }
            visible: target !== null
            x: target ? target.x : 0
            width: target ? target.width : 0
            y: 4
            height: parent.height - 8
            radius: Theme.innerRadius
            opacity: pill.focusedHere ? 1 : 0.45
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accent2 }
                GradientStop { position: 1; color: Theme.accent }
            }
            Behavior on x {
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
            }
            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
        }

        Row {
            id: buttons
            height: parent.height
            spacing: pill.compact ? 2 : 3

            Repeater {
                id: rep
                model: pill.last

                delegate: WsButton {
                    required property int index
                    num: index + 1
                    label: String(index + 1)
                    isActive: pill.active === num
                    occupied: pill.windows(num) > 0
                    isUrgent: pill.urgent(num) && !isActive
                    compact: pill.compact
                    onActivated: Actions.focusWorkspace(num)
                }
            }

            WsButton {
                id: more
                visible: pill.extra.length > 0
                num: 0
                label: pill.active > pill.last ? "…" + pill.active : "…"
                isActive: pill.active > pill.last
                occupied: true
                isUrgent: pill.extra.some(id => pill.urgent(id)) && !isActive
                compact: pill.compact
                tipText: "Workspaces: " + pill.extra.join(", ")
                bar: pill.bar
                onActivated: Actions.focusWorkspace("e+1")
                onSecondary: Actions.focusWorkspace("e-1")
            }
        }
    }

    component WsButton: Item {
        id: btn
        property int num
        property string label
        property bool isActive
        property bool occupied
        property bool isUrgent
        property bool compact
        property string tipText: ""
        property var bar: null
        signal activated
        signal secondary

        readonly property int pad: isActive ? (compact ? 10 : 14) : (compact ? 7 : 9)
        implicitWidth: text.implicitWidth + pad * 2
        width: implicitWidth
        height: parent.height
        Behavior on width {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            radius: Theme.innerRadius
            color: btn.isUrgent ? Theme.crit : mouse.containsMouse && !btn.isActive ? Theme.hover : "transparent"
            border.width: 1
            border.color: btn.isActive || btn.isUrgent || !btn.occupied ? "transparent"
                        : Qt.alpha(Theme.accent2, mouse.containsMouse ? 1 : 0.45)
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }

        Label {
            id: text
            anchors.centerIn: parent
            text: btn.label
            bold: btn.isActive
            font.pixelSize: btn.compact ? 13 : 14
            color: btn.isActive || btn.isUrgent ? Theme.accentInk
                 : btn.occupied || mouse.containsMouse ? Theme.text : Theme.faint
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: e => e.button === Qt.RightButton ? btn.secondary() : btn.activated()
            onContainsMouseChanged: {
                if (!btn.bar || !btn.tipText)
                    return;
                if (containsMouse)
                    btn.bar.showTip(btn, () => btn.tipText);
                else
                    btn.bar.hideTip(btn);
            }
        }
    }
}
