import QtQuick
import qs.services

// Lock, log out, suspend, reboot, shut down (wlogout).
Seg {
    id: seg

    padL: compact ? 6 : 7
    padR: compact ? 6 : 7
    hoverColor: Theme.crit
    tip: "Power menu"

    onClicked: Actions.launch([Actions.home + "/.config/wlogout/wlogout.sh"])

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F0425}"
        color: seg.hovered ? Theme.accentInk : Theme.crit
    }
}
