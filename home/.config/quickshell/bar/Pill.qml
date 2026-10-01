import QtQuick
import qs.services

// The floating rounded box every widget sits in. Its children are laid out in a row; it grows and
// shrinks smoothly with them.
Rectangle {
    id: pill

    default property alias content: row.data
    property var bar: null
    readonly property bool compact: bar ? bar.compact : false
    property bool shown: true
    property int padding: compact ? 3 : 4
    property alias spacing: row.spacing
    readonly property alias row: row

    implicitHeight: Theme.barHeight
    implicitWidth: row.implicitWidth + padding * 2
    width: implicitWidth
    visible: shown
    color: Theme.surface
    radius: Theme.radius
    border.width: 1
    border.color: Theme.border
    clip: true

    Behavior on width {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Row {
        id: row
        x: pill.padding
        height: parent.height
        spacing: 0
    }
}
