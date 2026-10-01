import QtQuick
import Quickshell.Services.UPower
import qs.services

// The battery (UPower): charge, time left, power draw, health, and the power profile
// (power-profiles-daemon).
Item {
    id: root

    property var popup
    property var bar
    readonly property var dev: UPower.displayDevice
    readonly property var battery: UPower.devices.values.find(d => d.isLaptopBattery) || null
    readonly property int percent: Math.round((dev ? dev.percentage : 0) * 100)
    readonly property bool charging: !!dev && dev.state === UPowerDeviceState.Charging

    implicitWidth: 350
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: 12

        Row {
            spacing: 12
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: Glyphs.battery(root.percent, root.charging)
                size: 30
                color: root.charging ? Theme.accent2 : Theme.levelColor(100 - root.percent)
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    text: root.percent + "%"
                    bold: true
                    font.pixelSize: 24
                }
                Label {
                    text: Battery.state(root.dev)
                    font.pixelSize: 13
                    dim: true
                }
            }
        }

        PMeter {
            width: parent.width
            percent: root.percent
            tone: root.charging ? Theme.accent2 : root.percent <= 12 ? Theme.crit : root.percent <= 25 ? Theme.warn : Theme.accent2
        }

        Row {
            spacing: 18
            Label {
                visible: !!root.dev && Math.abs(root.dev.changeRate) > 0.05
                text: (root.dev ? Math.abs(root.dev.changeRate).toFixed(1) : "") + " W"
                small: true
                dim: true
            }
            Label {
                visible: !!root.battery && root.battery.healthSupported
                text: "health " + (root.battery ? Math.round(root.battery.healthPercentage) : 0) + "%"
                small: true
                dim: true
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.separator
        }

        Caption { text: "Power profile" }
        Row {
            spacing: 6
            Repeater {
                model: [[PowerProfile.PowerSaver, "\u{F032A}", "Saver"], [PowerProfile.Balanced, "\u{F05D1}", "Balanced"],
                        [PowerProfile.Performance, "\u{F0463}", "Performance"]]
                delegate: PButton {
                    required property var modelData
                    visible: modelData[0] !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                    icon: modelData[1]
                    text: modelData[2]
                    checked: PowerProfiles.profile === modelData[0]
                    flat: !checked
                    onClicked: PowerProfiles.profile = modelData[0]
                }
            }
        }
    }
}
