import QtQuick
import qs.services

// Keep awake: while on, hypridle neither locks nor sleeps (an idle inhibitor on the bar, shell.qml).
Seg {
    id: seg

    padL: compact ? 6 : 7
    padR: compact ? 6 : 7
    tip: State.idleInhibited ? "Kept awake (no lock, no sleep)<br><font color='" + Theme.dim + "'>Click: allow idle again</font>"
                             : "Idle allowed<br><font color='" + Theme.dim + "'>Click: keep awake</font>"

    onClicked: State.idleInhibited = !State.idleInhibited

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: State.idleInhibited ? "\u{F0176}" : "\u{F0FAA}"
        color: State.idleInhibited ? Theme.accent : Theme.dim
    }
}
