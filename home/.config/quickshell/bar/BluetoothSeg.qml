import QtQuick
import Quickshell.Bluetooth
import qs.services

// Bluetooth (BlueZ): the symbol, in the accent while something is connected, with the battery of a
// connected device that reports one. Only on machines with an adapter. Click: devices · right: on/off.
Seg {
    id: seg

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: !!adapter && adapter.enabled
    readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []
    readonly property var withBattery: connected.find(d => d.batteryAvailable) || null

    shown: !!adapter
    padL: compact ? 6 : 7
    padR: compact ? 6 : (withBattery ? 8 : 7)
    spacing: 5
    tip: (!powered ? "Bluetooth off"
          : connected.length === 0 ? "Bluetooth on, nothing connected"
          : connected.map(d => Apps.esc(d.name || d.deviceName) + (d.batteryAvailable ? `<font color='${Theme.dim}'>  ·  ${Math.round(d.battery * 100)}%</font>` : "")).join("<br>"))
         + `<br><font color='${Theme.dim}'>Click: devices  ·  Right: on / off</font>`

    onClicked: button => {
        if (button === Qt.RightButton) {
            if (adapter)
                adapter.enabled = !adapter.enabled;
        } else
            togglePopup();
    }

    popupKey: "bluetooth"
    popupComponent: Component {
        BluetoothPopup {}
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: !seg.powered ? "\u{F00B2}" : seg.connected.length > 0 ? "\u{F00B1}" : "\u{F00AF}"
        color: !seg.powered ? Theme.dim : seg.connected.length > 0 ? Theme.accent : Theme.text
    }
    Label {
        visible: !seg.compact && !!seg.withBattery
        anchors.verticalCenter: parent.verticalCenter
        text: seg.withBattery ? Math.round(seg.withBattery.battery * 100) + "%" : ""
        font.pixelSize: 14
    }
}
