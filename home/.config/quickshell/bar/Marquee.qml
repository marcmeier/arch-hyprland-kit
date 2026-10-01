import QtQuick
import qs.services

// One line of text that slides through when it is wider than `maxWidth` (and `running`): a rest at the
// start, then it scrolls round, a gap between the end and the next start.
Item {
    id: marquee

    property string text: ""
    property int maxWidth: 240
    property bool running: true
    property alias font: first.font
    property alias color: first.color
    readonly property bool overflow: first.implicitWidth > maxWidth
    readonly property int gap: 48

    implicitWidth: Math.min(first.implicitWidth, maxWidth)
    implicitHeight: first.implicitHeight
    clip: true

    Item {
        id: strip
        height: parent.height
        width: first.implicitWidth * 2 + marquee.gap

        Label {
            id: first
            text: marquee.text
        }
        Label {
            visible: marquee.overflow
            x: first.implicitWidth + marquee.gap
            text: marquee.text
            font: first.font
            color: first.color
        }
    }

    SequentialAnimation {
        id: slide
        running: marquee.overflow && marquee.running && marquee.visible
        loops: Animation.Infinite
        PauseAnimation { duration: 2200 }
        NumberAnimation {
            target: strip
            property: "x"
            from: 0
            to: -(first.implicitWidth + marquee.gap)
            duration: (first.implicitWidth + marquee.gap) * 28
        }
        onRunningChanged: if (!running) strip.x = 0
    }
    onTextChanged: {
        strip.x = 0;
        if (slide.running)
            slide.restart();
    }
}
