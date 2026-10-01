import QtQuick
import qs.services

// A group from bar.jsonc as one pill: its members (minus the hidden ones) side by side, optionally
// with a thin line between them. It disappears when none of its members has anything to show.
Pill {
    id: group

    property string name: ""
    property bool separators: false
    readonly property var members: bar ? BarLayout.members(name, bar.variant) : []

    function shownAt(i) {
        const d = rep.itemAt(i);
        return !!(d && d.widget && d.widget.shown);
    }
    readonly property int firstShown: {
        for (let i = 0; i < rep.count; i++)
            if (shownAt(i))
                return i;
        return -1;
    }
    shown: firstShown >= 0

    Repeater {
        id: rep
        model: group.members

        delegate: Item {
            id: slot
            required property string modelData
            required property int index
            readonly property alias widget: loader.item
            readonly property bool line: group.separators && slot.index !== group.firstShown

            visible: !!(widget && widget.shown)
            implicitWidth: loader.implicitWidth + (line ? 1 : 0)
            implicitHeight: Theme.barHeight

            Rectangle {
                visible: slot.line
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.separator
            }

            Loader {
                id: loader
                x: slot.line ? 1 : 0
                sourceComponent: group.bar ? group.bar.widget(slot.modelData) : null
                onLoaded: item.bar = group.bar
            }
        }
    }
}
