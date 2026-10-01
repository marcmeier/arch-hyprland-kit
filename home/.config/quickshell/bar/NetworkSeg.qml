import QtQuick
import Quickshell.Networking
import qs.services

// The network (NetworkManager): Wi-Fi with its strength, "offline" without any connection, nothing at
// all on a wired connection. Click: the Wi-Fi networks.
Seg {
    id: seg

    readonly property var devices: Networking.devices.values
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi && d.connected) || null
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) || null
    readonly property var net: wifi ? wifi.networks.values.find(n => n.connected) || null : null
    readonly property real strength: net ? net.signalStrength : 0
    readonly property bool offline: !wifi && !wired
    readonly property bool hasWifi: devices.some(d => d.type === DeviceType.Wifi)

    shown: !wired || !!wifi
    padL: compact ? 6 : 8
    padR: compact ? 6 : 8
    spacing: 6
    tip: offline ? "Offline" : `${Apps.esc(net ? net.name : wifi.name)}<font color='${Theme.dim}'>  ·  ${Math.round(strength * 100)}%</font>`

    onClicked: {
        if (hasWifi)
            togglePopup();
        else
            Actions.launch(["ghostty", "-e", "nmtui"]);
    }

    popupKey: "network"
    popupComponent: Component {
        NetworkPopup {}
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: seg.offline ? "\u{F05AA}" : Glyphs.wifi(seg.strength)
        color: seg.offline ? Theme.warn : seg.compact ? Theme.text : Theme.accent
    }
    Label {
        visible: !seg.compact || seg.offline
        anchors.verticalCenter: parent.verticalCenter
        text: seg.offline ? "offline" : Math.round(seg.strength * 100) + "%"
        color: seg.offline ? Theme.warn : Theme.text
        font.pixelSize: seg.compact ? 13 : 14
    }
}
