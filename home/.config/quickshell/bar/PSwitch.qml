import QtQuick
import qs.services

// An on/off switch in a popup (Wi-Fi, Bluetooth). `toggled()` on a click; `checked` follows the thing.
Rectangle {
    id: sw

    property bool checked: false
    signal toggled

    implicitWidth: 42
    implicitHeight: 24
    radius: 12
    color: checked ? Theme.accent2 : Qt.alpha(Theme.overlay, Theme.light ? 0.16 : 0.12)
    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        y: 3
        x: sw.checked ? parent.width - width - 3 : 3
        color: sw.checked ? Theme.accentInk : Theme.knob
        Behavior on x {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}
