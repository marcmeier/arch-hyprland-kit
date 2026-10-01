import QtQuick
import Quickshell.Services.Pipewire
import qs.services

// Sound (PipeWire): the output and the microphone with their levels, every device to switch to, and
// the apps that play right now with a level each. The full mixer is one click away.
Item {
    id: root

    property var popup
    property var bar

    readonly property var nodes: Pipewire.nodes.values
    function real(n) {
        // the MiniFuse loopback is no place to send sound to
        return n.audio && !n.isStream && !/Line2/.test(n.name) && !/loopback/i.test(n.description);
    }
    readonly property var sinks: nodes.filter(n => n.isSink && real(n))
    readonly property var sources: nodes.filter(n => !n.isSink && real(n))
    // what plays: PipeWire counts a playback stream as a sink (it takes the app's sound)
    readonly property var apps: nodes.filter(n => n.isStream && n.isSink && n.audio)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: root.sinks.concat(root.sources, root.apps)
    }

    function name(n) {
        return n ? (n.description || n.nickname || n.name) : "";
    }

    implicitWidth: 340
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: 12

        Level {
            title: "Output"
            node: root.sink
            icon: Glyphs.volume(root.sink && root.sink.audio ? root.sink.audio.volume : 0, root.sink && root.sink.audio && root.sink.audio.muted, false)
        }
        Devices {
            visible: root.sinks.length > 1
            list: root.sinks
            current: root.sink
            onPicked: n => Pipewire.preferredDefaultAudioSink = n
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.separator
        }

        Level {
            title: "Microphone"
            node: root.source
            icon: Glyphs.mic(root.source && root.source.audio && root.source.audio.muted)
            muteColor: Theme.crit
        }
        Devices {
            visible: root.sources.length > 1
            list: root.sources
            current: root.source
            onPicked: n => Pipewire.preferredDefaultAudioSource = n
        }

        Column {
            visible: root.apps.length > 0
            width: parent.width
            spacing: 8
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.separator
            }
            Caption { text: "Apps" }
            Repeater {
                model: root.apps
                delegate: Item {
                    required property var modelData
                    readonly property var props: modelData.properties || {}
                    width: column.width
                    height: 40
                    Label {
                        width: parent.width - 50
                        elide: Text.ElideRight
                        text: props["application.name"] || modelData.description || modelData.nickname
                              || modelData.name.split(".").pop()
                        font.pixelSize: 12
                        dim: true
                    }
                    PSlider {
                        y: 18
                        width: parent.width - 50
                        value: modelData.audio.volume
                        dim: modelData.audio.muted
                        onMoved: v => modelData.audio.volume = v
                    }
                    PButton {
                        anchors.right: parent.right
                        y: 6
                        icon: modelData.audio.muted ? "\u{F075F}" : "\u{F057E}"
                        flat: true
                        onClicked: modelData.audio.muted = !modelData.audio.muted
                    }
                }
            }
        }

        PButton {
            icon: "\u{F062E}"
            text: "Mixer"
            onClicked: {
                Actions.launch(["pwvucontrol"]);
                root.popup.close();
            }
        }
    }

    // a device's level: name, mute button, slider, percent
    component Level: Column {
        id: level
        property string title
        property var node
        property string icon
        property color muteColor: Theme.dim
        readonly property bool muted: !!(node && node.audio && node.audio.muted)
        width: column.width
        spacing: 6

        Caption { text: level.title }
        Item {
            width: parent.width
            height: 34
            PButton {
                id: mute
                anchors.verticalCenter: parent.verticalCenter
                icon: level.icon
                iconSize: 17
                implicitWidth: 36
                checked: false
                onClicked: if (level.node) level.node.audio.muted = !level.node.audio.muted
            }
            Column {
                x: mute.width + 10
                width: parent.width - x - 48
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.name(level.node)
                    font.pixelSize: 12
                    color: level.muted ? level.muteColor : Theme.text
                }
                PSlider {
                    width: parent.width
                    value: level.node && level.node.audio ? level.node.audio.volume : 0
                    dim: level.muted
                    onMoved: v => {
                        if (level.node && level.node.audio)
                            level.node.audio.volume = v;
                    }
                }
            }
            Label {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: level.muted ? "muted" : Math.round((level.node && level.node.audio ? level.node.audio.volume : 0) * 100) + "%"
                font.pixelSize: 12
                color: level.muted ? level.muteColor : Theme.text
            }
        }
    }

    // the devices to switch to; the current one is marked
    component Devices: Column {
        id: devices
        property var list: []
        property var current
        signal picked(var node)
        width: column.width
        spacing: 2
        Repeater {
            model: devices.list
            delegate: Rectangle {
                required property var modelData
                readonly property bool isCurrent: modelData === devices.current
                width: devices.width
                height: 30
                radius: 8
                color: isCurrent ? Qt.alpha(Theme.accent2, 0.15) : hover.containsMouse ? Theme.hover : "transparent"
                Icon {
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.isCurrent ? "\u{F012C}" : ""
                    size: 14
                    color: Theme.accent2
                }
                Label {
                    x: 30
                    width: parent.width - 38
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: root.name(modelData)
                    font.pixelSize: 13
                    color: parent.isCurrent ? Theme.text : Theme.dim
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: devices.picked(modelData)
                }
            }
        }
    }
}
