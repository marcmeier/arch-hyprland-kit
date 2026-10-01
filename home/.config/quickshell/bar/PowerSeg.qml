import QtQuick
import qs.services

// Lock, log out, suspend, reboot, shut down: the power menu (power/PowerMenu.qml).
Seg {
    id: seg

    padL: compact ? 6 : 7
    padR: compact ? 6 : 7
    hoverColor: Theme.crit
    tip: "Power menu<br><font color='" + Theme.dim + "'>Click: lock, log out, suspend, reboot, shut down  ·  Right: lock</font>"

    onClicked: button => {
        if (button === Qt.RightButton)
            Session.lock();
        else
            Session.powerMenu();
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F0425}"
        color: seg.hovered ? Theme.accentInk : Theme.crit
    }
}
