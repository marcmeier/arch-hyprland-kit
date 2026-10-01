import QtQuick
import qs.services

// Notifications (mako): a bell with the number waiting, crossed out in do-not-disturb.
// Click: do not disturb · right: bring back the last one · middle: dismiss all.
Seg {
    id: seg

    readonly property var d: Feeds.notifications.data
    readonly property int count: d?.count ?? 0
    readonly property bool dnd: !!(d && d.dnd)

    padL: compact ? 6 : 7
    padR: compact ? 6 : 7
    spacing: 4
    tip: (dnd ? "Do not disturb (notifications are held)" : count > 0 ? `${count} notification(s)` : "No notifications")
         + `<br><font color='${Theme.dim}'>Click: do not disturb  ·  Right: bring back last  ·  Middle: dismiss all</font>`

    onClicked: button => {
        const cmd = button === Qt.RightButton ? ["makoctl", "restore"] : button === Qt.MiddleButton ? ["makoctl", "dismiss", "-a"]
                  : ["makoctl", "mode", "-t", "dnd"];
        Feeds.runThen(cmd, "notifications");
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: seg.dnd ? "\u{F009B}" : seg.count > 0 ? "\u{F009E}" : "\u{F009A}"
        color: seg.dnd ? Theme.warn : seg.count > 0 ? Theme.accent2 : Theme.dim
    }
    Label {
        visible: seg.count > 0
        anchors.verticalCenter: parent.verticalCenter
        text: seg.count
        color: seg.dnd ? Theme.warn : Theme.accent2
        font.pixelSize: seg.compact ? 13 : 14
    }
}
