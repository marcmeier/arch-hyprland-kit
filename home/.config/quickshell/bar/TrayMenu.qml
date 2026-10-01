import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.services

// A tray app's menu (DBusMenu), drawn like the rest of the shell. A submenu opens in place, with a
// way back at the top.
Item {
    id: root

    property var popup
    property var bar
    property var menu: null
    property var stack: []                     // the submenus opened on the way down
    readonly property var current: stack.length ? stack[stack.length - 1] : menu

    implicitWidth: 240
    implicitHeight: column.implicitHeight

    onMenuChanged: stack = []

    QsMenuOpener {
        id: opener
        menu: root.current
    }

    Column {
        id: column
        width: parent.width
        spacing: 1

        Rectangle {
            visible: root.stack.length > 0
            width: parent.width
            height: 30
            radius: 8
            color: back.containsMouse ? Theme.hover : "transparent"
            Icon {
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F0141}"
                size: 14
                color: Theme.dim
            }
            Label {
                x: 28
                anchors.verticalCenter: parent.verticalCenter
                text: root.stack.length ? root.stack[root.stack.length - 1].text.replace(/_/g, "") : ""
                font.pixelSize: 13
                bold: true
            }
            MouseArea {
                id: back
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.stack = root.stack.slice(0, -1)
            }
        }

        Repeater {
            model: opener.children
            delegate: Item {
                id: entry
                required property var modelData
                width: column.width
                height: modelData.isSeparator ? 9 : 30

                Rectangle {
                    visible: entry.modelData.isSeparator
                    anchors.centerIn: parent
                    width: parent.width - 8
                    height: 1
                    color: Theme.separator
                }

                Rectangle {
                    visible: !entry.modelData.isSeparator
                    anchors.fill: parent
                    radius: 8
                    color: mouse.containsMouse && entry.modelData.enabled ? Theme.hover : "transparent"
                    opacity: entry.modelData.enabled ? 1 : 0.45

                    // check box / radio button state, or the item's icon
                    Item {
                        id: lead
                        x: 6
                        width: 18
                        height: parent.height
                        Icon {
                            visible: entry.modelData.buttonType !== QsMenuButtonType.None
                            anchors.centerIn: parent
                            size: 14
                            text: entry.modelData.checkState === Qt.Checked
                                  ? (entry.modelData.buttonType === QsMenuButtonType.RadioButton ? "\u{F0133}" : "\u{F0132}")
                                  : (entry.modelData.buttonType === QsMenuButtonType.RadioButton ? "\u{F0130}" : "\u{F0131}")
                            color: entry.modelData.checkState === Qt.Checked ? Theme.accent2 : Theme.dim
                        }
                        IconImage {
                            visible: entry.modelData.buttonType === QsMenuButtonType.None && entry.modelData.icon !== ""
                            anchors.centerIn: parent
                            implicitSize: 16
                            source: entry.modelData.icon
                            // symbolic icons come dark: draw them in the text colour
                            layer.enabled: /symbolic/.test(entry.modelData.icon)
                            layer.effect: MultiEffect {
                                colorization: 1
                                colorizationColor: Theme.dim
                                brightness: 1
                            }
                        }
                    }
                    Label {
                        x: 32
                        width: parent.width - 56
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: entry.modelData.text.replace(/_(?=\S)/g, "")
                        font.pixelSize: 13
                    }
                    Icon {
                        visible: entry.modelData.hasChildren
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F0142}"
                        size: 14
                        color: Theme.dim
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: entry.modelData.enabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (entry.modelData.hasChildren) {
                                root.stack = root.stack.concat([entry.modelData]);
                            } else {
                                entry.modelData.triggered();
                                root.popup.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
