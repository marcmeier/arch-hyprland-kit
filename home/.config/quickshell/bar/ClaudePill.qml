import QtQuick
import qs.services

// Claude Code usage (scripts/claude-usage.py): the 5-hour session and the week in percent (compact:
// the one closer to its limit). Click: both limits with their resets and the tokens per day.
Pill {
    id: pill

    readonly property var d: Feeds.claude.data
    shown: !!d
    readonly property color tone: !d ? Theme.text
                                : d.level === "crit" ? Theme.crit
                                : d.level === "warn" ? Theme.warn
                                : d.level === "stale" ? Theme.dim : Theme.text

    Seg {
        id: seg
        bar: pill.bar
        padL: pill.compact ? 10 : 12
        padR: pill.compact ? 10 : 12
        spacing: 6
        tip: Usage.summary(pill.d)
        onClicked: togglePopup()

        popupKey: "claude"
        popupComponent: Component {
            ClaudePopup {}
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F06A9}"
            size: 15
            color: pill.d && pill.d.level === "ok" ? Theme.accent2 : pill.tone
        }
        Repeater {
            model: !pill.d ? [] : !pill.d.session ? [["today", Usage.count(pill.d.today || 0)]]
                 : pill.compact ? [["", Math.max(pill.d.session.pct, pill.d.week.pct) + "%"]]
                 : [["5h", pill.d.session.pct + "%"], ["7d", pill.d.week.pct + "%"]]
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
                    color: pill.tone
                    font.pixelSize: pill.compact ? 13 : 14
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
}
