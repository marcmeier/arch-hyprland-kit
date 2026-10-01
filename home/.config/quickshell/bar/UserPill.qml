import QtQuick
import qs.services

// You: the round avatar (theme/apply.py renders it from ~/.face) and your name. A click opens the
// desktop settings (bar/SettingsPopup.qml: wallpaper, bar size and widgets, monitors, sync, keys).
Pill {
    id: pill

    readonly property var members: bar ? BarLayout.members("group/user", bar.variant) : []
    readonly property bool showAvatar: members.includes("custom/avatar")
    readonly property bool showName: members.includes("custom/username")
    shown: showAvatar || showName

    Seg {
        bar: pill.bar
        padL: pill.showAvatar ? 2 : 10
        padR: pill.showName ? 10 : 2
        spacing: 8
        tip: "Desktop settings<br><font color='" + Theme.dim + "'>wallpaper · bar size and widgets · monitors · sync · keys</font>"
        onClicked: togglePopup()
        popupKey: "settings"
        popupComponent: Component {
            SettingsPopup {}
        }

        Item {
            visible: pill.showAvatar
            width: 26
            height: 26
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: avatar
                anchors.fill: parent
                sourceSize: Qt.size(52, 52)
                fillMode: Image.PreserveAspectCrop
                cache: false
                smooth: true
                mipmap: true
                // a new picture: load it again
                source: Theme.avatarVersion >= 0 ? "file://" + Theme.avatar : ""
                Connections {
                    target: Theme
                    function onAvatarVersionChanged() {
                        avatar.source = "";
                        avatar.source = "file://" + Theme.avatar;
                    }
                }
            }
        }

        Label {
            visible: pill.showName
            anchors.verticalCenter: parent.verticalCenter
            text: Feeds.userName
            bold: true
            font.pixelSize: pill.compact ? 13 : 14
        }
    }
}
