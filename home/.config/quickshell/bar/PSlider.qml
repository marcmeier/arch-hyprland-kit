import QtQuick
import qs.services

// A level from 0 to 1: drag, click or turn the wheel. `moved(value)` while you change it; `value`
// follows the thing it controls.
Item {
    id: slider

    property real value: 0
    property bool dim: false
    property real step: 0.02
    readonly property real shown: drag.pressed ? dragValue : value
    property real dragValue: 0
    signal moved(real value)

    implicitWidth: 240
    implicitHeight: 22

    function set(v) {
        v = Math.max(0, Math.min(1, v));
        dragValue = v;
        moved(v);
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Qt.rgba(1, 1, 1, 0.10)

        Rectangle {
            width: Math.max(height, track.width * slider.shown)
            height: parent.height
            radius: parent.radius
            opacity: slider.dim ? 0.4 : 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accent2 }
                GradientStop { position: 1; color: Theme.accent }
            }
        }
    }

    Rectangle {
        id: knob
        width: drag.pressed || drag.containsMouse ? 16 : 12
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(slider.width - width, slider.width * slider.shown - width / 2))
        color: Theme.text
        border.width: 2
        border.color: slider.dim ? Theme.dim : Theme.accent2
        Behavior on width {
            NumberAnimation { duration: 120 }
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: m => slider.set(m.x / slider.width)
        onPositionChanged: m => {
            if (pressed)
                slider.set(m.x / slider.width);
        }
        onWheel: w => slider.set(slider.value + (w.angleDelta.y > 0 ? slider.step : -slider.step))
    }
}
