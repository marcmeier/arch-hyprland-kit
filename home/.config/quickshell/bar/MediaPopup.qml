import QtQuick
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.services

// Now playing in detail (MPRIS): cover, title, artist, album, where it is (click to jump there), the
// controls, and every player that runs (click one to show it in the bar).
Item {
    id: root

    property var popup
    property var bar
    readonly property var p: Media.player

    implicitWidth: 360
    implicitHeight: column.implicitHeight

    Component.onCompleted: Media.watchers++
    Component.onDestruction: Media.watchers--

    Column {
        id: column
        width: parent.width
        spacing: 14

        Row {
            spacing: 14
            width: parent.width

            ClippingRectangle {
                width: 84
                height: 84
                radius: 12
                color: Theme.well
                Image {
                    id: art
                    anchors.fill: parent
                    source: root.p ? root.p.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(168, 168)
                    asynchronous: true
                    smooth: true
                }
                Icon {
                    visible: art.status !== Image.Ready
                    anchors.centerIn: parent
                    text: "\u{F075A}"
                    size: 32
                    color: Theme.faint
                }
            }

            Column {
                width: parent.width - 98
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.p ? (root.p.trackTitle || root.p.identity) : ""
                    bold: true
                    font.pixelSize: 15
                }
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: root.p ? root.p.trackArtist : ""
                    font.pixelSize: 13
                }
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: root.p ? root.p.trackAlbum : ""
                    small: true
                    dim: true
                }
                Label {
                    text: root.p ? root.p.identity : ""
                    small: true
                    color: Theme.accent2
                }
            }
        }

        // ---- where it is ----
        Column {
            visible: !!root.p && root.p.lengthSupported && root.p.length > 0
            width: parent.width
            spacing: 4
            PSlider {
                width: parent.width
                value: root.p && root.p.length > 0 ? root.p.position / root.p.length : 0
                onMoved: v => {
                    if (root.p && root.p.canSeek)
                        root.p.position = v * root.p.length;
                }
            }
            Item {
                width: parent.width
                height: 14
                Label {
                    text: Media.time(root.p ? root.p.position : 0)
                    small: true
                    dim: true
                }
                Label {
                    anchors.right: parent.right
                    text: Media.time(root.p ? root.p.length : 0)
                    small: true
                    dim: true
                }
            }
        }

        // ---- controls ----
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            PButton {
                visible: !!root.p && root.p.shuffleSupported
                icon: "\u{F049D}"
                flat: !(root.p && root.p.shuffle)
                checked: !!root.p && root.p.shuffle
                onClicked: root.p.shuffle = !root.p.shuffle
            }
            PButton {
                icon: "\u{F04AE}"
                iconSize: 18
                implicitWidth: 44
                enabled: !!root.p && root.p.canGoPrevious
                onClicked: root.p.previous()
            }
            PButton {
                icon: root.p && root.p.isPlaying ? "\u{F03E4}" : "\u{F040A}"
                iconSize: 22
                implicitWidth: 56
                implicitHeight: 40
                accent: true
                onClicked: root.p.togglePlaying()
            }
            PButton {
                icon: "\u{F04AD}"
                iconSize: 18
                implicitWidth: 44
                enabled: !!root.p && root.p.canGoNext
                onClicked: root.p.next()
            }
            PButton {
                visible: !!root.p && root.p.loopSupported
                icon: root.p && root.p.loopState === MprisLoopState.Track ? "\u{F0458}" : "\u{F0456}"
                flat: !(root.p && root.p.loopState !== MprisLoopState.None)
                checked: !!root.p && root.p.loopState !== MprisLoopState.None
                onClicked: root.p.loopState = root.p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                             : root.p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
            }
        }

        // ---- the players, when there is more than one ----
        Column {
            visible: Media.players.length > 1
            width: parent.width
            spacing: 6
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.separator
            }
            Caption { text: "Players" }
            Repeater {
                model: Media.players
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 32
                    radius: 8
                    color: modelData === root.p ? Qt.alpha(Theme.accent2, 0.15) : pick.containsMouse ? Theme.hover : "transparent"
                    Icon {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.isPlaying ? "\u{F040A}" : "\u{F03E4}"
                        size: 14
                        color: modelData.isPlaying ? Theme.accent2 : Theme.dim
                    }
                    Label {
                        x: 34
                        width: parent.width - 42
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: modelData.identity + (modelData.trackTitle ? "  ·  " + modelData.trackTitle : "")
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: pick
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Media.chosen = modelData
                    }
                }
            }
        }
    }
}
