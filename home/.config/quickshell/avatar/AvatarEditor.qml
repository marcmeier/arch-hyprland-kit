import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.services
import "../bar"

// Placing your picture (settings: a click on it, or "Picture …"): the chosen image behind a round
// mask, the way the bar, the lock and the login screen will cut it. Drag to move it, the wheel or the
// slider to zoom; "Use this picture" hands the square to scripts/settings-menu.sh avatar-save as
// fractions of the image, which writes ~/.face and renders it. Enter: use it · Esc: cancel.
Scope {
    id: root

    property string path: ""
    readonly property bool open: path !== ""

    readonly property int view: 320         // the square you place the picture in
    readonly property real imgW: photo.implicitWidth
    readonly property real imgH: photo.implicitHeight
    readonly property bool ready: photo.status === Image.Ready && imgW > 0 && imgH > 0
    readonly property real baseScale: ready ? view / Math.min(imgW, imgH) : 1
    property real zoom: 1                   // 1 (the short side fills the circle) to maxZoom
    readonly property real maxZoom: 5
    readonly property real scale: baseScale * zoom
    property real ox: 0                     // where the image's top left corner is in the square
    property real oy: 0

    function edit(file) {
        path = file;
        zoom = 1;
        placeLater.restart();
        focusLater.restart();
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const target = Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0];
        if (target && win.screen !== target)
            win.screen = target;
    }
    function cancel() {
        path = "";
    }

    // a portrait mostly has the face in its upper part: start a little above the middle
    function place() {
        if (!ready)
            return;
        ox = clampX((view - imgW * scale) / 2);
        oy = clampY(imgH > imgW ? view / 2 - imgH * scale * 0.38 : (view - imgH * scale) / 2);
    }
    Timer {
        id: focusLater
        interval: 50
        onTriggered: card.forceActiveFocus()
    }
    Timer {
        id: placeLater
        interval: 30
        onTriggered: root.place()
    }
    Connections {
        target: photo
        function onStatusChanged() {
            if (photo.status === Image.Ready)
                root.place();
        }
    }

    // the image always covers the square
    function clampX(x) {
        return Math.min(0, Math.max(view - imgW * scale, x));
    }
    function clampY(y) {
        return Math.min(0, Math.max(view - imgH * scale, y));
    }
    // zoom around a point of the square (the pointer, or the middle)
    function zoomTo(z, px, py) {
        z = Math.max(1, Math.min(maxZoom, z));
        const sx = (px - ox) / scale, sy = (py - oy) / scale;
        zoom = z;
        ox = clampX(px - sx * scale);
        oy = clampY(py - sy * scale);
    }

    function save() {
        if (!ready)
            return;
        saver.command = [Quickshell.shellDir + "/scripts/settings-menu.sh", "avatar-save", path,
            String(-ox / scale / imgW), String(-oy / scale / imgH), String(view / scale / imgW)];
        saver.startDetached();
        path = "";
    }
    Process {
        id: saver
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
        WlrLayershell.namespace: "driftless-avatar"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: Theme.scrim
            opacity: root.open ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.open ? 180 : 220; easing.type: Easing.OutCubic }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.cancel()
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: root.view + 64
            height: content.implicitHeight + 56
            radius: 20
            color: Theme.card
            border.width: 1
            border.color: Qt.alpha(Theme.primary, 0.25)
            opacity: backdrop.opacity
            scale: 0.96 + 0.04 * backdrop.opacity
            focus: root.open
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) {
                    root.cancel();
                    e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    root.save();
                    e.accepted = true;
                }
            }
            // a click on the card stays on it
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: content
                x: 32
                y: 28
                width: root.view
                spacing: 14

                Label {
                    text: "Your picture"
                    bold: true
                    font.pixelSize: 16
                }

                // ---- the square: the image, the round cut darkened around ----
                Item {
                    id: square
                    width: root.view
                    height: root.view
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.well
                    }
                    Image {
                        id: photo
                        x: root.ox
                        y: root.oy
                        width: root.imgW * root.scale
                        height: root.imgH * root.scale
                        source: root.path !== "" ? "file://" + root.path : ""
                        sourceSize: Qt.size(2048, 2048)
                        autoTransform: true
                        asynchronous: true
                        cache: false
                        smooth: true
                        mipmap: true
                    }
                    // outside the circle: dimmed (a ring wide enough to reach the corners)
                    Rectangle {
                        readonly property real ring: root.view / 4
                        anchors.centerIn: parent
                        width: root.view + 2 * ring
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: ring
                        border.color: Qt.rgba(8 / 255, 9 / 255, 12 / 255, 0.62)
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.alpha(Theme.primary, 0.7)
                    }

                    MouseArea {
                        id: drag
                        anchors.fill: parent
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property real lastX: 0
                        property real lastY: 0
                        onPressed: m => {
                            lastX = m.x;
                            lastY = m.y;
                        }
                        onPositionChanged: m => {
                            root.ox = root.clampX(root.ox + m.x - lastX);
                            root.oy = root.clampY(root.oy + m.y - lastY);
                            lastX = m.x;
                            lastY = m.y;
                        }
                        onWheel: w => root.zoomTo(root.zoom * Math.pow(1.1, w.angleDelta.y / 120), w.x, w.y)
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: photo.status === Image.Error
                        text: "Cannot read this image"
                        color: Theme.crit
                    }
                }

                // ---- zoom ----
                Row {
                    width: parent.width
                    spacing: 10
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F06EC}"
                        color: Theme.dim
                    }
                    PSlider {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 2 * (zoomIcon.width + parent.spacing)
                        value: (root.zoom - 1) / (root.maxZoom - 1)
                        onMoved: v => root.zoomTo(1 + v * (root.maxZoom - 1), root.view / 2, root.view / 2)
                    }
                    Icon {
                        id: zoomIcon
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F06ED}"
                        color: Theme.dim
                    }
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    small: true
                    dim: true
                    lineHeight: 1.15
                    text: "Drag to move, scroll to zoom. Let your face fill most of the circle: in the bar it is only a few millimetres wide."
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8
                    PButton {
                        text: "Other …"
                        flat: true
                        onClicked: {
                            root.cancel();
                            other.startDetached();
                        }
                    }
                    PButton {
                        text: "Cancel"
                        onClicked: root.cancel()
                    }
                    PButton {
                        text: "Use this picture"
                        accent: true
                        enabled: root.ready
                        onClicked: root.save()
                    }
                }
            }
        }
    }
    Process {
        id: other
        command: [Quickshell.shellDir + "/scripts/settings-menu.sh", "avatar"]
    }

    IpcHandler {
        target: "avatar"

        // place IMAGE as your picture (scripts/settings-menu.sh avatar, after the file chooser)
        function edit(file: string): bool {
            root.edit(file);
            return true;
        }
    }
}
