import QtQuick
import qs.services

// A part of a pill that does something: hover highlight, clicks (left, middle, right), the wheel,
// and a tooltip after a moment on it. Its children are laid out in a row.
Item {
    id: seg

    default property alias content: row.data
    property var bar: null
    readonly property bool compact: bar ? bar.compact : false
    property bool shown: true          // false: the bar leaves it out (visible would hide it for good)
    property int padL: compact ? 7 : 9
    property int padR: compact ? 7 : 9
    property alias spacing: row.spacing
    property string tip: ""            // rich text (<b>, <font color>, <br>); empty: no tooltip
    property bool interactive: true
    property color hoverColor: Theme.hover
    readonly property bool hovered: mouse.containsMouse
    // the popup this part opens (its name for the IPC: "popup calendar")
    property string popupKey: ""
    property Component popupComponent: null

    function togglePopup() {
        if (bar && popupComponent)
            bar.togglePopup(seg, popupComponent, popupKey);
    }
    onBarChanged: if (bar && popupKey) bar.registerPopup(popupKey, seg)

    signal clicked(int button)
    signal scrolled(int steps)         // +1 up, -1 down

    implicitWidth: row.implicitWidth + padL + padR
    implicitHeight: Theme.barHeight
    visible: shown

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Theme.innerRadius
        color: seg.hoverColor
        opacity: seg.interactive && mouse.containsMouse ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    Row {
        id: row
        x: seg.padL
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: seg.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        property real wheelRest: 0

        onClicked: mouse => {
            if (seg.bar) {
                seg.bar.hideTip(seg);
                // a part without a popup of its own closes the open one
                if (!seg.popupComponent)
                    seg.bar.closePopup();
            }
            seg.clicked(mouse.button);
        }
        onWheel: wheel => {
            wheelRest += wheel.angleDelta.y;
            const steps = Math.trunc(wheelRest / 120);
            if (steps !== 0) {
                wheelRest -= steps * 120;
                seg.scrolled(steps);
            }
        }
        onContainsMouseChanged: {
            if (!seg.bar)
                return;
            if (containsMouse && seg.tip)
                seg.bar.showTip(seg, () => seg.tip);
            else
                seg.bar.hideTip(seg);
        }
    }
}
