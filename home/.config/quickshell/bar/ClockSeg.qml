import QtQuick
import Quickshell
import qs.services

// Time and date. Click: the month with your events · right click: ikhal (add and edit events).
Seg {
    id: seg

    padL: compact ? 10 : 12
    padR: compact ? 10 : 12
    spacing: compact ? 8 : 10

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ISO 8601 week
    function week(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        return Math.ceil(((t - new Date(Date.UTC(t.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7);
    }

    tip: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy") + "<font color='" + Theme.dim + "'>  ·  week "
         + week(clock.date) + "</font>"

    onClicked: button => {
        if (button === Qt.RightButton)
            Actions.script("ikhal.sh");
        else
            togglePopup();
    }

    popupKey: "calendar"
    popupComponent: Component {
        CalendarPopup {}
    }

    Label {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, "HH:mm")
        bold: true
        font.pixelSize: seg.compact ? 14 : 15
        font.letterSpacing: seg.compact ? 0.5 : 1
    }
    Label {
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 1
        text: Qt.formatDateTime(clock.date, "ddd dd MMM")
        small: true
        dim: true
        font.weight: Font.Normal
    }
}
