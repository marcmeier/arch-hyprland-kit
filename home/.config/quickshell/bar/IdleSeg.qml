import QtQuick
import qs.services

// Keep awake: while on, hypridle neither locks nor turns the screen off (services/KeepAwake.qml).
Seg {
    id: seg

    padL: compact ? 6 : 7
    padR: compact ? 6 : 7
    tip: KeepAwake.on ? "Kept awake (no lock, no screen off)<br><font color='" + Theme.dim + "'>Click: allow idle again</font>"
                      : "Idle allowed<br><font color='" + Theme.dim + "'>Click: keep awake</font>"

    onClicked: KeepAwake.on = !KeepAwake.on

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: KeepAwake.on ? "\u{F0176}" : "\u{F0FAA}"
        color: KeepAwake.on ? Theme.accent : Theme.dim
    }
}
