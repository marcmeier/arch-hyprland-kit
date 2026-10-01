import QtQuick
import qs.services

// Claude Code usage (scripts/claude-usage.py), next to the ask button: the 5-hour session and the week
// in percent (compact: the one closer to its limit). Click: both limits with their resets and the
// tokens per day.
Seg {
    id: seg

    readonly property var d: Feeds.claude.data
    readonly property color tone: !d ? Theme.text
                                : d.level === "crit" ? Theme.crit
                                : d.level === "warn" ? Theme.warn
                                : d.level === "stale" ? Theme.dim : Theme.text

    shown: !!d
    padL: compact ? 4 : 5
    padR: compact ? 10 : 12
    spacing: 6
    tip: Usage.summary(d)
    onClicked: togglePopup()

    popupKey: "claude"
    popupComponent: Component {
        ClaudePopup {}
    }

    Repeater {
        model: !seg.d ? [] : !seg.d.session ? [["today", Usage.count(seg.d.today || 0)]]
             : seg.compact ? [["", Math.max(seg.d.session.pct, seg.d.week.pct) + "%"]]
             : [["5h", seg.d.session.pct + "%"], ["7d", seg.d.week.pct + "%"]]
        delegate: Row {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Label {
                visible: text !== "" && parent.modelData[0] !== "today"
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 1
                text: parent.modelData[0]
                small: true
                color: Theme.faint
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.modelData[1]
                color: seg.tone
                font.pixelSize: seg.compact ? 13 : 14
            }
            Label {
                visible: parent.modelData[0] === "today"
                anchors.verticalCenter: parent.verticalCenter
                text: "today"
                small: true
                color: Theme.faint
            }
        }
    }
}
