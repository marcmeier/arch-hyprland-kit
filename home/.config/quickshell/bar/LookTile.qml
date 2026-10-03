import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services

// One choice of the look in the settings: the desktop in miniature (your wallpaper, the bar's pills,
// a window), dark, light, or both halves for auto. `look`: dark, light or auto.
Item {
    id: tile

    property string look: "dark"
    property string label: ""
    property string icon: ""
    property bool selected: false
    signal clicked

    implicitWidth: 112
    implicitHeight: preview.height + 8 + caption.implicitHeight

    readonly property var looks: Theme.looks
    readonly property var dark: looks.dark || {}
    readonly property var light: looks.light || {}

    Rectangle {
        id: preview
        width: parent.width
        height: Math.round(width * 0.62)
        radius: 11
        color: "transparent"
        border.width: tile.selected ? 2 : 1
        border.color: tile.selected ? Theme.accent2 : mouse.containsMouse ? Qt.alpha(Theme.overlay, 0.28) : Theme.cardBorder
        Behavior on border.color {
            ColorAnimation { duration: 150 }
        }

        Item {
            id: screen
            anchors.fill: parent
            anchors.margins: tile.selected ? 4 : 3
            Behavior on anchors.margins {
                NumberAnimation { duration: 150 }
            }
            // rounded like the frame
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Image {
                id: wall
                anchors.fill: parent
                readonly property string file: "file://" + Quickshell.env("HOME") + "/.config/wall.png"
                source: file
                sourceSize: Qt.size(320, 180)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                // a new wallpaper has the same path: load it again after every render
                Connections {
                    target: Theme
                    function onRendersChanged() {
                        wall.source = "";
                        wall.source = wall.file;
                    }
                }
            }

            // dark, light, or both side by side
            Mini {
                width: tile.look === "auto" ? parent.width / 2 : parent.width
                height: parent.height
                c: tile.look === "light" ? tile.light : tile.dark
            }
            Mini {
                visible: tile.look === "auto"
                x: parent.width / 2
                width: parent.width / 2
                height: parent.height
                c: tile.light
                offset: parent.width / 2
            }
            // the seam of auto: a thin line of light
            Rectangle {
                visible: tile.look === "auto"
                x: parent.width / 2
                width: 1
                height: parent.height
                color: Qt.rgba(1, 1, 1, 0.55)
            }
        }
        Rectangle {
            id: mask
            anchors.fill: screen
            radius: preview.radius - screen.anchors.margins
            visible: false
            layer.enabled: true
        }
    }

    Row {
        id: caption
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: preview.bottom
        anchors.topMargin: 8
        spacing: 5
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            text: tile.icon
            size: 13
            color: tile.selected ? Theme.accent2 : Theme.dim
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: tile.label
            font.pixelSize: 12
            bold: tile.selected
            color: tile.selected ? Theme.text : Theme.dim
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.clicked()
    }

    // the desktop in miniature in the colours `c` (colors.json "looks"); `offset`: where this half
    // starts, so both halves of auto draw one desktop
    component Mini: Item {
        id: mini
        property var c: ({})
        property real offset: 0
        clip: true

        Item {
            x: -mini.offset
            width: screen.width
            height: screen.height

            // the bar: three pills
            Row {
                x: 4
                y: 4
                spacing: 3
                Rectangle {
                    width: 18
                    height: 7
                    radius: 3.5
                    color: Qt.alpha(mini.c.glass || "#14161c", 0.82)
                    Rectangle {
                        x: 2
                        y: 2
                        width: 6
                        height: 3
                        radius: 1.5
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: mini.c.primary || "#33ccff" }
                            GradientStop { position: 1; color: mini.c.secondary || "#00ff99" }
                        }
                    }
                }
                Rectangle {
                    width: screen.width - 4 * 2 - 18 - 26 - 6
                    height: 7
                    radius: 3.5
                    color: Qt.alpha(mini.c.glass || "#14161c", 0.82)
                    Rectangle {
                        anchors.centerIn: parent
                        width: 14
                        height: 2
                        radius: 1
                        color: mini.c.fg || "#d7dce2"
                        opacity: 0.8
                    }
                }
                Rectangle {
                    width: 26
                    height: 7
                    radius: 3.5
                    color: Qt.alpha(mini.c.glass || "#14161c", 0.82)
                    Rectangle {
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 4
                        height: 4
                        radius: 2
                        color: mini.c.primary || "#33ccff"
                    }
                    Rectangle {
                        x: 11
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11
                        height: 2
                        radius: 1
                        color: mini.c.dim || "#8b93a1"
                    }
                }
            }

            // a window with a little text and a button
            Rectangle {
                x: Math.round(screen.width * 0.14)
                y: 15
                width: Math.round(screen.width * 0.72)
                height: screen.height - 15 - 6
                radius: 4
                color: mini.c.bg || "#14161c"
                border.width: 1
                border.color: Qt.alpha(mini.c.overlay || "#ffffff", 0.10)

                Column {
                    x: 6
                    y: 6
                    spacing: 3
                    Rectangle { width: 30; height: 3; radius: 1.5; color: mini.c.fg || "#d7dce2" }
                    Rectangle { width: 44; height: 2; radius: 1; color: mini.c.dim || "#8b93a1" }
                    Rectangle { width: 36; height: 2; radius: 1; color: mini.c.dim || "#8b93a1" }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 5
                    width: 16
                    height: 6
                    radius: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: mini.c.primary || "#33ccff" }
                        GradientStop { position: 1; color: mini.c.secondary || "#00ff99" }
                    }
                }
            }
        }
    }
}
