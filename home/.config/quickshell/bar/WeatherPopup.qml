import QtQuick
import qs.services

// The weather in detail (scripts/weather.py, wttr.in): now, the next hours and three days.
Item {
    id: root

    property var popup
    property var bar
    readonly property var w: Feeds.weather.data || {}

    implicitWidth: 330
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: 12

        // ---- now ----
        Row {
            spacing: 14
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.w.icon || ""
                size: 40
                color: Theme.accent2
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Row {
                    spacing: 8
                    Label {
                        text: (root.w.temp ?? "") + "°"
                        bold: true
                        font.pixelSize: 28
                    }
                    Label {
                        anchors.baseline: parent.children[0].baseline
                        text: "feels " + (root.w.feels ?? "") + "°"
                        dim: true
                        font.pixelSize: 13
                    }
                }
                Label {
                    text: (root.w.desc || "") + (root.w.place ? "  ·  " + root.w.place : "")
                    font.pixelSize: 13
                }
            }
        }

        Row {
            spacing: 18
            Row {
                spacing: 4
                Icon { text: "\u{F058E}"; size: 14; color: Theme.dim }
                Label { anchors.verticalCenter: parent.verticalCenter; text: (root.w.humidity ?? "") + "%"; small: true }
            }
            Row {
                spacing: 4
                Icon { text: "\u{F059D}"; size: 14; color: Theme.dim }
                Label { anchors.verticalCenter: parent.verticalCenter; text: root.w.wind || ""; small: true }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.separator
        }

        // ---- the next hours ----
        Caption { text: "Next hours" }
        Row {
            width: parent.width
            Repeater {
                model: root.w.hours || []
                delegate: Column {
                    required property var modelData
                    width: column.width / Math.max(1, (root.w.hours || []).length)
                    spacing: 3
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.time
                        small: true
                        dim: true
                    }
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.icon
                        size: 18
                        color: Theme.accent2
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.temp + "°"
                        font.pixelSize: 13
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.rain + "%"
                        small: true
                        color: modelData.rain >= 50 ? Theme.accent2 : Theme.faint
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.separator
        }

        // ---- three days ----
        Caption { text: "Next days" }
        Column {
            width: parent.width
            spacing: 6
            Repeater {
                model: root.w.days || []
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: 24
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 100
                        text: modelData.label
                        font.pixelSize: 13
                    }
                    Icon {
                        x: 104
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.icon
                        size: 16
                        color: Theme.accent2
                    }
                    Label {
                        x: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F058C} " + modelData.rain + "%"
                        small: true
                        color: modelData.rain >= 50 ? Theme.accent2 : Theme.faint
                    }
                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.min + "°  " + modelData.max + "°"
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
