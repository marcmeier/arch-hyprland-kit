import QtQuick
import Quickshell.Networking
import qs.services

// Wi-Fi (NetworkManager): on/off, the networks around, strongest first. Click a known network to join
// it; a new one asks for its password in nmtui. Settings: nm-connection-editor.
Item {
    id: root

    property var popup
    property var bar

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var networks: wifi ? wifi.networks.values.filter(n => n.name !== "")
                                              .sort((a, b) => (b.connected - a.connected) || (b.known - a.known)
                                                              || (b.signalStrength - a.signalStrength)).slice(0, 9) : []

    // look for networks while the popup is open
    Component.onCompleted: if (wifi) wifi.scannerEnabled = true
    Component.onDestruction: if (wifi) wifi.scannerEnabled = false

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
                    text: Networking.wifiEnabled ? "\u{F0928}" : "\u{F05AA}"
                    size: 20
                    color: Networking.wifiEnabled ? Theme.accent2 : Theme.dim
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wi-Fi"
                    bold: true
                    font.pixelSize: 15
                }
            }
            // the switch
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                height: 24
                radius: 12
                color: Networking.wifiEnabled ? Theme.accent2 : Qt.rgba(1, 1, 1, 0.12)
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    y: 3
                    x: Networking.wifiEnabled ? parent.width - width - 3 : 3
                    color: Networking.wifiEnabled ? Theme.accentInk : Theme.text
                    Behavior on x {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }
        }

        Label {
            visible: Networking.wifiEnabled && root.networks.length === 0
            text: "Looking for networks …"
            dim: true
            font.pixelSize: 13
        }

        Column {
            visible: Networking.wifiEnabled
            width: parent.width
            spacing: 2
            Repeater {
                model: root.networks
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool busy: modelData.stateChanging
                    width: column.width
                    height: 36
                    radius: 9
                    color: modelData.connected ? Qt.alpha(Theme.accent2, 0.15) : mouse.containsMouse ? Theme.hover : "transparent"

                    Icon {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: Glyphs.wifi(modelData.signalStrength)
                        size: 16
                        color: modelData.connected ? Theme.accent2 : Theme.text
                    }
                    Label {
                        x: 38
                        width: parent.width - 110
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: modelData.name
                        font.pixelSize: 13
                        bold: modelData.connected
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.busy ? "…" : modelData.connected ? "connected" : modelData.known ? "known" : ""
                            small: true
                            color: modelData.connected ? Theme.accent2 : Theme.faint
                        }
                        Icon {
                            visible: modelData.security !== WifiSecurityType.Open
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{F033E}"
                            size: 12
                            color: Theme.faint
                        }
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const n = row.modelData;
                            if (n.connected)
                                n.disconnect();
                            else if (n.known || n.security === WifiSecurityType.Open)
                                n.connect();
                            else {
                                Actions.launch(["ghostty", "-e", "nmtui-connect", n.name]);
                                root.popup.close();
                            }
                        }
                    }
                }
            }
        }

        PButton {
            icon: "\u{F0493}"
            text: "Network settings"
            onClicked: {
                Actions.launch(["nm-connection-editor"]);
                root.popup.close();
            }
        }
    }
}
