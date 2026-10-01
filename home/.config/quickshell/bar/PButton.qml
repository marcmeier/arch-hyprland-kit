import QtQuick
import qs.services

// A button in a popup: a glyph and/or a word. `accent`: filled with the accent gradient (the main
// action); `checked`: marked as the current choice.
Rectangle {
    id: btn

    property string icon: ""
    property string text: ""
    property bool accent: false
    property bool checked: false
    property bool flat: false
    property int iconSize: 15
    property int padX: text ? 12 : 8
    signal clicked

    implicitWidth: row.implicitWidth + padX * 2
    implicitHeight: 32
    opacity: enabled ? 1 : 0.4
    radius: Theme.innerRadius
    color: accent ? "transparent" : checked ? Qt.alpha(Theme.accent2, 0.18)
         : mouse.containsMouse ? Theme.hover : flat ? "transparent" : Theme.well
    border.width: checked ? 1 : 0
    border.color: Qt.alpha(Theme.accent2, 0.6)
    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    Rectangle {
        visible: btn.accent
        anchors.fill: parent
        radius: parent.radius
        opacity: mouse.containsMouse ? 1 : 0.88
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.accent2 }
            GradientStop { position: 1; color: Theme.accent }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Icon {
            visible: btn.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.icon
            size: btn.iconSize
            color: btn.accent ? Theme.accentInk : btn.checked ? Theme.accent2 : Theme.text
        }
        Label {
            visible: btn.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            font.pixelSize: 13
            bold: btn.accent
            color: btn.accent ? Theme.accentInk : Theme.text
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
