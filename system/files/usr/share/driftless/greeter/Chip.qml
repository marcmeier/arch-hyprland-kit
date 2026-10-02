import QtQuick

// A quiet button at the bottom of the login screen: an icon and maybe a word, lit on hover.
Rectangle {
    id: chip
    required property var theme
    property string icon
    property string label
    property bool clickable: true
    signal clicked
    width: chipRow.implicitWidth + 24
    height: 32
    radius: 10
    color: clickable && chipMouse.containsMouse ? chip.theme.hover : "transparent"
    Behavior on color {
        ColorAnimation { duration: 120 }
    }
    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: chip.theme.font
            font.pixelSize: 15
            color: chip.clickable && chipMouse.containsMouse ? chip.theme.text : chip.theme.dim
            text: chip.icon
            renderType: Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.label !== ""
            font.family: chip.theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
            color: chip.clickable && chipMouse.containsMouse ? chip.theme.text : chip.theme.dim
            text: chip.label
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }
    }
    MouseArea {
        id: chipMouse
        anchors.fill: parent
        enabled: chip.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
