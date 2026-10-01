import QtQuick
import qs.services

// The driftless sync (scripts/sync.py): the GitHub mark in the colour of its state, plus what waits
// (↓ incoming, ↑ outgoing). Click: the sync menu · right: sync now · middle: pause / resume.
Seg {
    id: seg

    readonly property var d: Feeds.sync.data
    readonly property string mode: d?.["class"] ?? "none"
    shown: !!d && mode !== "none"
    padL: compact ? 6 : 7
    padR: compact ? 6 : 8
    tip: (d?.tooltip ?? "").replace(/\n/g, "<br>").replace(/(^|<br>)( +)/g, (m, br, sp) => br + "&nbsp;".repeat(sp.length))

    onClicked: button => {
        const arg = button === Qt.RightButton ? ["now"] : button === Qt.MiddleButton ? ["toggle"] : [];
        Feeds.runThen(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--", Actions.scripts + "/sync-menu.sh"].concat(arg), "sync");
    }

    Label {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: seg.d?.text ?? ""
        font.pixelSize: seg.compact ? 14 : 15
        color: seg.mode === "running" ? Theme.accent : seg.mode === "pending" || seg.mode === "off" ? Theme.warn
             : seg.mode === "error" ? Theme.crit : Theme.dim

        // a sync is running: breathe
        SequentialAnimation on opacity {
            running: seg.mode === "running"
            loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) label.opacity = 1
        }
    }
}
