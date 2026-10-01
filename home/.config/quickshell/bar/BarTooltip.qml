import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The tooltip below a bar: a card that fades in under the item after a moment and follows it from
// item to item. It never takes clicks (empty input region).
PanelWindow {
    id: win

    property var bar
    property Item target: null
    property var textFn: null
    property bool open: false
    property real anchorX: 0

    screen: bar.screen
    anchors {
        top: true
        left: true
        right: true
    }
    margins.top: bar.implicitHeight + 6
    implicitHeight: 400
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || card.opacity > 0.01
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "driftless-tooltip"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function place() {
        if (target)
            anchorX = target.mapToItem(null, target.width / 2, 0).x;
    }
    function show(item, fn) {
        target = item;
        textFn = fn;
        if (open)
            place();
        else
            delay.restart();
    }
    function hide(item) {
        if (item && item !== target)
            return;
        delay.stop();
        open = false;
    }

    Timer {
        id: delay
        interval: 450
        onTriggered: {
            win.place();
            win.open = true;
        }
    }

    Rectangle {
        id: card
        readonly property string text: win.textFn ? win.textFn() : ""
        width: Math.min(label.implicitWidth, 520) + 24
        height: label.implicitHeight + 16
        x: Math.round(Math.max(Theme.barSide, Math.min(win.width - width - Theme.barSide, win.anchorX - width / 2)))
        y: win.open ? 0 : -4
        opacity: win.open && text !== "" ? 1 : 0
        color: Theme.card
        radius: 12
        border.width: 1
        border.color: Theme.cardBorder

        Behavior on opacity {
            NumberAnimation { duration: win.open ? 140 : 100 }
        }
        Behavior on y {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on x {
            enabled: card.opacity > 0.5
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Text {
            id: label
            x: 12
            y: 8
            width: Math.min(implicitWidth, 520)
            text: card.text
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            lineHeight: 1.15
            renderType: Text.NativeRendering
        }
    }
}
