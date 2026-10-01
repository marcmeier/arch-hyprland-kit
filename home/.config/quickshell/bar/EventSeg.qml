import QtQuick
import qs.services

// The next event within two days (khal, scripts/agenda.py); compact: the icon lights up instead.
// Click: ikhal · right click: sync the calendars now.
Seg {
    id: seg

    readonly property var c: Feeds.calendar.data
    readonly property var next: c ? c.next : null
    readonly property bool failed: !!(c && c.error)
    readonly property string label: next ? (next.when ? next.when + " " : "") + next.title : ""

    spacing: 8

    function agendaTip() {
        if (!c)
            return "";
        const lines = [];
        if (c.error)
            lines.push(`<font color='${Theme.warn}'>⚠ Sync failed: ${Apps.esc(c.error)}</font>`, "");
        const days = (c.agenda || []).slice(0, 3);
        if (!days.length)
            lines.push(`<font color='${Theme.dim}'>No events in the next days</font>`);
        for (const day of days) {
            lines.push(`<b>${day.label}</b> <font color='${Theme.dim}'>${day.sub}</font>`);
            for (const e of day.events) {
                const time = e.allDay ? "all day" : e.continued ? "until " + e.end : e.start;
                lines.push(`&nbsp;&nbsp;<font color='${Theme.accent2}'>${time}</font>&nbsp;&nbsp;${Apps.esc(e.title)}`);
            }
        }
        lines.push("", `<font color='${Theme.dim}'>Click: calendar  ·  Right: sync now</font>`);
        return lines.join("<br>");
    }
    tip: agendaTip()

    onClicked: button => {
        if (button === Qt.RightButton)
            Feeds.runThen([Actions.scripts + "/calendar-sync.sh"], "calendar");
        else
            Actions.script("ikhal.sh");
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: seg.failed ? "\u{F0026}" : "\u{F00ED}"
        size: 16
        color: seg.failed ? Theme.warn : seg.next ? Theme.accent2 : Theme.dim
    }
    Label {
        visible: !seg.compact && seg.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 260)
        elide: Text.ElideRight
        text: seg.label
        font.pixelSize: 13
        font.weight: Font.Normal
        color: Qt.alpha(Theme.text, 0.75)
    }
}
