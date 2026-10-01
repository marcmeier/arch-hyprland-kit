import QtQuick
import QtQuick.Effects

// A "living" orb: three soft blobs circle a core and melt together through blur. Speed and size
// follow the bubble's mode.
Item {
    id: orb

    property string mode: "idle"
    property real level: 0          // 0..1, the microphone or the voice
    // the theme's accents (from the wallpaper) and its error colour
    property color primary: "#33ccff"
    property color secondary: "#00ff99"
    property color error: "#ff5f6d"

    implicitWidth: 30
    implicitHeight: 30

    readonly property bool isError: mode === "error"
    readonly property color cCore: isError ? error : Qt.tint(primary, Qt.alpha(secondary, 0.35))
    readonly property var cBlobs: isError
        ? [error, Qt.lighter(error, 1.3), Qt.darker(error, 1.5)]
        : [primary, secondary, Qt.darker(primary, 1.5)]

    // target speed, eased
    property real speed: mode === "thinking" ? 4.2
                       : mode === "listening" ? 2.0
                       : mode === "error" ? 0.8
                       : 1.0
    Behavior on speed { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }

    property real smoothLevel: 0
    Behavior on smoothLevel { NumberAnimation { duration: 90 } }
    onLevelChanged: smoothLevel = level

    property real t: 0
    FrameAnimation {
        running: orb.visible && orb.opacity > 0
        onTriggered: orb.t += frameTime * orb.speed
    }

    Item {
        id: blobs
        anchors.centerIn: parent
        width: orb.width * 1.6
        height: orb.height * 1.6
        visible: false
        layer.enabled: true

        readonly property real cx: width / 2
        readonly property real cy: height / 2

        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real phase: index * 2.094
                readonly property real pulse: 1 + 0.18 * Math.sin(orb.t * 1.7 + phase * 1.3)
                                                + orb.smoothLevel * 0.45
                readonly property real r: orb.width * (0.17 + 0.05 * Math.sin(orb.t * 0.9 + phase))
                width: orb.width * 0.52 * pulse
                height: width
                radius: width / 2
                color: orb.cBlobs[index]
                x: blobs.cx + r * Math.cos(orb.t * (1 + index * 0.25) + phase) - width / 2
                y: blobs.cy + r * Math.sin(orb.t * (1 + index * 0.25) + phase) - height / 2
            }
        }

        Rectangle {
            width: orb.width * (0.5 + orb.smoothLevel * 0.25)
            height: width
            radius: width / 2
            anchors.centerIn: parent
            color: orb.cCore
        }
    }

    // soft glow behind
    MultiEffect {
        source: blobs
        anchors.fill: blobs
        blurEnabled: true
        blurMax: 32
        blur: 1.0
        opacity: 0.55 + orb.smoothLevel * 0.3
        scale: 1.25
    }

    // the orb itself, slightly blurred for the "goo" look
    MultiEffect {
        source: blobs
        anchors.fill: blobs
        blurEnabled: true
        blurMax: 6
        blur: 0.3
        saturation: 0.1
    }
}
