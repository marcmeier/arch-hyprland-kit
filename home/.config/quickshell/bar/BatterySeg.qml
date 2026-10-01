import QtQuick
import Quickshell.Services.UPower
import qs.services

// The battery (UPower; only on machines that have one). Click: time left, power draw and the power
// profile.
Seg {
    id: seg

    readonly property var dev: UPower.displayDevice
    readonly property int percent: Math.round((dev ? dev.percentage : 0) * 100)
    readonly property bool charging: !!dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged
                                               || dev.state === UPowerDeviceState.PendingCharge)
    readonly property color tone: charging ? Theme.accent2 : percent <= 12 ? Theme.crit : percent <= 25 ? Theme.warn : Theme.text

    shown: !!dev && dev.isLaptopBattery && dev.isPresent
    padL: compact ? 5 : 6
    padR: compact ? 6 : 8
    spacing: compact ? 4 : 6
    tip: Battery.summary(dev)

    onClicked: togglePopup()

    popupKey: "battery"
    popupComponent: Component {
        BatteryPopup {}
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: Glyphs.battery(seg.percent, seg.charging)
        color: seg.tone
    }
    Label {
        anchors.verticalCenter: parent.verticalCenter
        text: seg.percent + "%"
        color: seg.tone
        font.pixelSize: seg.compact ? 13 : 14
    }
}
