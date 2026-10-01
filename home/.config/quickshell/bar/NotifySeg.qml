import QtQuick
import qs.services

// Notifications (services/Notifs.qml): a bell with the number waiting, in the accent while some are
// new, crossed out in do not disturb. Click: the list · right: do not disturb · middle: clear all.
Seg {
    id: seg

    readonly property int count: Notifs.count
    readonly property bool dnd: Notifs.dnd
    readonly property bool fresh: Notifs.unread > 0

    padL: compact ? 6 : 7
    padR: compact ? 6 : 7
    spacing: 4
    tip: (dnd ? "Do not disturb (only critical ones pop up)" : count > 0 ? `${count} notification${count === 1 ? "" : "s"}` : "No notifications")
         + (!dnd && Notifs.fullscreen ? `<br><font color='${Theme.dim}'>Quiet while a window is fullscreen</font>` : "")
         + (dnd && count > 0 ? `<font color='${Theme.dim}'>  ·  ${count} waiting</font>` : "")
         + `<br><font color='${Theme.dim}'>Click: list  ·  Right: do not disturb  ·  Middle: clear all</font>`

    onClicked: button => {
        if (button === Qt.RightButton)
            Notifs.setDnd(!Notifs.dnd);
        else if (button === Qt.MiddleButton)
            Notifs.clear();
        else
            togglePopup();
    }

    popupKey: "notifications"
    popupComponent: Component {
        NotifyPopup {}
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: seg.dnd ? "\u{F009B}" : seg.count > 0 ? "\u{F009E}" : "\u{F009A}"
        color: seg.dnd ? Theme.warn : seg.fresh ? Theme.accent2 : seg.count > 0 ? Theme.text : Theme.dim
    }
    Label {
        visible: seg.count > 0
        anchors.verticalCenter: parent.verticalCenter
        text: seg.count
        color: seg.dnd ? Theme.warn : seg.fresh ? Theme.accent2 : Theme.dim
        font.pixelSize: seg.compact ? 13 : 14
    }
}
