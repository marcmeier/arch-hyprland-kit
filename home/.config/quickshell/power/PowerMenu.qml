import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.services
import "../bar"

// The power menu (SUPER + SHIFT + M, the power button in the bar; wlogout before): lock, log out,
// suspend, reboot, shut down as five cards over the dimmed, blurred focused screen. Keys: the letter
// on a card, arrows and Enter, Esc or a click beside the cards to go back.
//   quickshell ipc -p ~/.config/quickshell call power toggle      (open, close)
Scope {
    id: root

    property bool open: false
    property int current: 0

    readonly property var items: [
        { key: "L", glyph: "\u{F033E}", text: "Lock", danger: false, run: () => Session.lock() },
        { key: "E", glyph: "\u{F0343}", text: "Log out", danger: true, run: () => Session.logout() },
        { key: "U", glyph: "\u{F04B2}", text: "Suspend", danger: false, run: () => Session.suspend() },
        { key: "R", glyph: "\u{F0709}", text: "Reboot", danger: false, run: () => Session.reboot() },
        { key: "S", glyph: "\u{F0425}", text: "Shut down", danger: true, run: () => Session.poweroff() }
    ]

    function show() {
        if (Session.locked)
            return;
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const target = Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0];
        if (target && win.screen !== target)
            win.screen = target;
        current = 0;
        uptime.reload();
        open = true;
    }
    function hide() {
        open = false;
    }
    function pick(i) {
        hide();
        items[i].run();
    }

    Connections {
        target: Session
        function onLockRequested() {
            root.hide();
        }
        function onPowerMenuRequested() {
            root.open ? root.hide() : root.show();
        }
    }

    IpcHandler {
        target: "power"
        function toggle(): void {
            root.open ? root.hide() : root.show();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.hide();
        }
    }

    // "up 3 h 12 min"
    FileView {
        id: uptime
        path: "/proc/uptime"
        readonly property int seconds: Math.floor(parseFloat(text()) || 0)
    }
    FileView {
        id: hostname
        path: "/etc/hostname"
    }
    function since(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return "up " + (d > 0 ? d + " d " + h + " h" : h > 0 ? h + " h " + m + " min" : m + " min");
    }

    PanelWindow {
        id: win

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.open || backdrop.opacity > 0.01
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "driftless-power"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: Qt.rgba(8 / 255, 9 / 255, 12 / 255, 0.6)
            opacity: root.open ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.open ? 180 : 220; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: root.open
            Keys.onPressed: e => {
                const n = root.items.length;
                if (e.key === Qt.Key_Escape)
                    root.hide();
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab || e.key === Qt.Key_Down)
                    root.current = (root.current + 1) % n;
                else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || e.key === Qt.Key_Up)
                    root.current = (root.current + n - 1) % n;
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)
                    root.pick(root.current);
                else {
                    const i = root.items.findIndex(it => it.key === e.text.toUpperCase());
                    if (i >= 0)
                        root.pick(i);
                    else
                        return;
                }
                e.accepted = true;
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 26
            opacity: backdrop.opacity
            scale: 0.96 + 0.04 * backdrop.opacity

            // who and since when
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    sourceSize: Qt.size(80, 80)
                    source: Theme.avatarVersion >= 0 ? "file://" + Theme.avatar : ""
                    cache: false
                    smooth: true
                    mipmap: true
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Label {
                        text: Feeds.userName
                        bold: true
                        font.pixelSize: 15
                    }
                    Label {
                        small: true
                        dim: true
                        text: hostname.text().trim() + "  ·  " + root.since(uptime.seconds)
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                Repeater {
                    model: root.items

                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool active: root.current === index
                        readonly property color tone: modelData.danger ? Theme.crit : Theme.accent2

                        width: 148
                        height: 156
                        radius: 18
                        color: active ? Qt.rgba(40 / 255, 44 / 255, 54 / 255, 0.95) : Theme.card
                        border.width: 1
                        border.color: active ? tone : Theme.cardBorder
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }

                        // each card comes in a moment after the one before
                        opacity: root.open ? 1 : 0
                        transform: Translate {
                            y: root.open ? 0 : 14
                            Behavior on y {
                                SequentialAnimation {
                                    PauseAnimation { duration: root.open ? tile.index * 28 : 0 }
                                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation { duration: root.open ? tile.index * 28 : 0 }
                                NumberAnimation { duration: 200 }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 12
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: 34
                                text: tile.modelData.glyph
                                color: tile.active ? tile.tone : Theme.dim
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.text
                                bold: true
                                font.pixelSize: 13
                                color: tile.active ? Theme.text : Theme.dim
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 22
                                height: 20
                                radius: 6
                                color: "transparent"
                                border.width: 1
                                border.color: tile.active ? Qt.alpha(tile.tone, 0.6) : Qt.rgba(1, 1, 1, 0.12)
                                Label {
                                    anchors.centerIn: parent
                                    text: tile.modelData.key
                                    small: true
                                    font.pixelSize: 11
                                    color: tile.active ? tile.tone : Theme.faint
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.current = tile.index
                            onClicked: root.pick(tile.index)
                        }
                    }
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                small: true
                color: Theme.faint
                text: "←  →  choose   ·   Enter   ·   Esc  back"
            }
        }
    }
}
