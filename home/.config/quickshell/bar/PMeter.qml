import QtQuick
import qs.services

// A bar that shows how much of something is used (0..100), in the accent, orange from 70, red from 90.
Rectangle {
    id: meter

    property real percent: 0
    property color tone: Theme.levelColor(percent)

    implicitWidth: 260
    implicitHeight: 8
    radius: height / 2
    color: Qt.alpha(Theme.overlay, 0.08)

    Rectangle {
        width: Math.max(parent.height, parent.width * Math.min(meter.percent, 100) / 100)
        height: parent.height
        radius: parent.radius
        color: meter.tone
        Behavior on width {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }
    }
}
