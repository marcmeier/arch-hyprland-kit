import QtQuick
import qs.services

// Ask Claude by voice, without knowing SUPER + A: click to talk, click again to send; right click
// stops everything. The bubble grows out of this button; the sparkles show what it does (red while
// it listens, breathing while Claude thinks).
Seg {
    id: seg

    readonly property string script: Actions.home + "/.config/hypr/notch/notch.py"
    readonly property bool listening: Voice.mode === "listening"
    readonly property bool busy: Voice.mode === "thinking" || Voice.speaking

    padL: compact ? 9 : 11
    padR: compact ? 4 : 5
    tip: listening ? "Listening …<br><font color='" + Theme.dim + "'>Click: send  ·  Right: stop</font>"
                   : "Ask Claude<br><font color='" + Theme.dim + "'>Click: talk, click again: send  ·  Right: stop  ·  SUPER + A</font>"

    onBarChanged: if (bar) Voice.register(bar.modelData.name, seg)
    onClicked: button => Actions.launch([script, button === Qt.RightButton ? "cancel" : "toggle"])

    Icon {
        id: icon
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F0674}"
        size: 16
        color: seg.listening ? Theme.crit : Voice.mode !== "idle" ? Theme.accent : Theme.accent2

        SequentialAnimation on opacity {
            running: seg.listening || seg.busy
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: seg.listening ? 550 : 800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: seg.listening ? 550 : 800; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) icon.opacity = 1
        }
    }
}
