import QtQuick
import qs.services
import "../notifications"

// The bell's popup: every notification that is still there, newest first and grouped by app, with
// do not disturb and "clear all". Opening it marks them as seen (the bell stops glowing).
Item {
    id: root

    property var popup
    property var bar

    implicitWidth: 400
    implicitHeight: column.implicitHeight

    Component.onCompleted: {
        Notifs.markRead();
        Notifs.now = Date.now();
        Notifs.listOpen = true;
    }
    Component.onDestruction: Notifs.listOpen = false

    Column {
        id: column
        width: parent.width
        spacing: 12

        Item {
            width: parent.width
            height: 32
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Caption {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Notifs.count > 0
                    small: true
                    color: Theme.faint
                    text: Notifs.count
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                PButton {
                    icon: "\u{F009B}"
                    text: "Do not disturb"
                    checked: Notifs.dnd
                    onClicked: Notifs.setDnd(!Notifs.dnd)
                }
                PButton {
                    visible: Notifs.count > 0
                    icon: "\u{F039F}"
                    text: "Clear"
                    onClicked: Notifs.clear()
                }
            }
        }

        // nothing there
        Column {
            visible: Notifs.count === 0
            width: parent.width
            topPadding: 18
            bottomPadding: 22
            spacing: 8
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                size: 34
                text: Notifs.dnd ? "\u{F009B}" : "\u{F009C}"
                color: Theme.faint
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "All caught up"
                color: Theme.dim
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Notifs.dnd
                small: true
                color: Theme.faint
                text: "Do not disturb: only critical ones pop up"
            }
        }

        ListView {
            id: list
            visible: Notifs.count > 0
            width: parent.width
            height: Math.min(contentHeight, Math.round((root.bar ? root.bar.screen.height : 1200) * 0.62))
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: Notifs.history

            section.property: "app"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                required property string section
                width: ListView.view.width
                height: 30
                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40
                    elide: Text.ElideRight
                    small: true
                    bold: true
                    color: Theme.dim
                    text: parent.section
                }
                PButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: 24
                    flat: true
                    icon: "\u{F0156}"
                    iconSize: 12
                    onClicked: Notifs.clearApp(parent.section)
                }
            }

            delegate: NotifCard {
                width: ListView.view.width
                showApp: false
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: 160 }
                    NumberAnimation { property: "x"; to: 60; duration: 200; easing.type: Easing.InCubic }
                }
            }
            // a card that is still coming in when it moves finishes coming in
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; to: 1; duration: 200 }
                NumberAnimation { property: "x"; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }
}
