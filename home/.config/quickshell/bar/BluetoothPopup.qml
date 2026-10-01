import QtQuick
import Quickshell.Bluetooth
import qs.services

// Bluetooth (BlueZ), like the Wi-Fi popup: on/off, your devices (click: connect or disconnect, with
// their battery), and while the popup is open the devices nearby (click: pair, trust and connect).
// Settings and file transfer: blueman.
Item {
    id: root

    property var popup
    property var bar

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: !!adapter && adapter.enabled
    readonly property var all: adapter ? adapter.devices.values : []
    readonly property var mine: all.filter(d => d.paired || d.bonded)
                                   .sort((a, b) => (b.connected - a.connected) || name(a).localeCompare(name(b)))
    // nearby: only the ones that say who they are
    readonly property var nearby: all.filter(d => !d.paired && !d.bonded && d.name && d.name !== d.address).slice(0, 8)

    function name(d) {
        return d.name || d.deviceName || d.address;
    }

    // look for devices while the popup is open
    function scan() {
        if (powered && !adapter.discovering)
            adapter.discovering = true;
    }
    Component.onCompleted: scan()
    onPoweredChanged: scan()
    Component.onDestruction: if (adapter && adapter.discovering) adapter.discovering = false

    implicitWidth: 320
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: 10

        Item {
            width: parent.width
            height: 32
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.powered ? "\u{F00AF}" : "\u{F00B2}"
                    size: 20
                    color: root.powered ? Theme.accent2 : Theme.dim
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Bluetooth"
                    bold: true
                    font.pixelSize: 15
                }
            }
            PSwitch {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.powered
                onToggled: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
            }
        }

        Caption {
            visible: root.powered
            text: "Your devices"
        }
        Label {
            visible: root.powered && root.mine.length === 0
            text: "None paired yet: pick one nearby"
            dim: true
            font.pixelSize: 13
        }
        Column {
            visible: root.powered
            width: parent.width
            spacing: 2
            Repeater {
                model: root.mine
                delegate: DeviceRow {}
            }
        }

        Item {
            visible: root.powered
            width: parent.width
            height: 16
            Caption {
                anchors.verticalCenter: parent.verticalCenter
                text: "Nearby"
            }
            // searching: three dots that breathe, like the lock screen's check
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: root.adapter && root.adapter.discovering
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 5
                        height: 5
                        radius: 2.5
                        color: Theme.accentAt(index / 2)
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 160 }
                            NumberAnimation { from: 0.2; to: 1; duration: 380 }
                            NumberAnimation { from: 1; to: 0.2; duration: 380 }
                            PauseAnimation { duration: (2 - index) * 160 }
                        }
                    }
                }
            }
        }
        Label {
            visible: root.powered && root.nearby.length === 0
            text: "Looking for devices …  (put yours in pairing mode)"
            dim: true
            font.pixelSize: 13
            width: parent.width
            wrapMode: Text.Wrap
        }
        Column {
            visible: root.powered
            width: parent.width
            spacing: 2
            Repeater {
                model: root.nearby
                delegate: DeviceRow {}
            }
        }

        PButton {
            icon: "\u{F00B3}"
            text: "Bluetooth settings"
            onClicked: {
                Actions.launch(["blueman-manager"]);
                root.popup.close();
            }
        }
    }

    // one device: its kind, its name, what it is doing; a click does the obvious next thing
    component DeviceRow: Rectangle {
        id: row
        required property var modelData
        readonly property var dev: modelData
        readonly property bool mine: dev.paired || dev.bonded
        readonly property bool busy: dev.pairing || dev.state === BluetoothDeviceState.Connecting
                                     || dev.state === BluetoothDeviceState.Disconnecting
        // after pairing: trust it and connect
        property bool connectWhenPaired: false

        width: column.width
        height: 36
        radius: 9
        color: dev.connected ? Qt.alpha(Theme.accent2, 0.15) : mouse.containsMouse ? Theme.hover : "transparent"

        Connections {
            target: row.dev
            function onPairedChanged() {
                if (row.dev.paired && row.connectWhenPaired) {
                    row.connectWhenPaired = false;
                    row.dev.trusted = true;
                    row.dev.connect();
                }
            }
        }

        Icon {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            text: Glyphs.bluetoothDevice(row.dev.icon)
            size: 16
            color: row.dev.connected ? Theme.accent2 : row.mine ? Theme.text : Theme.dim
        }
        Label {
            x: 38
            width: parent.width - 120
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.name(row.dev)
            font.pixelSize: 13
            bold: row.dev.connected
            color: row.mine ? Theme.text : Theme.dim
        }
        Label {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            small: true
            color: row.dev.connected ? Theme.accent2 : Theme.faint
            text: row.busy ? "…"
                : row.dev.connected ? (row.dev.batteryAvailable ? Math.round(row.dev.battery * 100) + "%  ·  " : "") + "connected"
                : row.mine ? "" : "pair"
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (row.busy)
                    return;
                if (row.dev.connected)
                    row.dev.disconnect();
                else if (row.mine)
                    row.dev.connect();
                else {
                    row.connectWhenPaired = true;
                    row.dev.pair();
                }
            }
        }
    }
}
