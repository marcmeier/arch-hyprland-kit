import QtQuick
import qs.services

// Claude Code usage in detail (scripts/claude-usage.py): both limits with their resets, the tokens
// of the last days on this machine, and the usage page on claude.ai.
Item {
    id: root

    property var popup
    property var bar
    readonly property var d: Feeds.claude.data || {}

    implicitWidth: 360
    implicitHeight: column.implicitHeight

    // the reset countdowns move on while the popup is open
    property var now: new Date()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Column {
        id: column
        width: parent.width
        spacing: 12

        Row {
            spacing: 10
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F06A9}"
                size: 22
                color: Theme.accent2
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: "Claude Code usage"
                bold: true
                font.pixelSize: 15
            }
        }

        Repeater {
            model: root.d.session ? [["Session", "5 hours", root.d.session], ["Week", "7 days", root.d.week]] : []
            delegate: Column {
                required property var modelData
                width: column.width
                spacing: 6
                Item {
                    width: parent.width
                    height: 18
                    Label {
                        text: modelData[0]
                        font.pixelSize: 13
                        bold: true
                    }
                    Label {
                        x: 72
                        text: modelData[1]
                        small: true
                        dim: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        anchors.right: parent.right
                        text: modelData[2].pct + "%"
                        bold: true
                        color: Theme.levelColor(modelData[2].pct)
                    }
                }
                PMeter {
                    width: parent.width
                    percent: modelData[2].pct
                }
                Label {
                    text: root.now && Usage.resets(modelData[2])
                    small: true
                    dim: true
                }
            }
        }

        Label {
            visible: !root.d.session
            width: parent.width
            wrapMode: Text.Wrap
            text: "The usage API does not answer (login expired? start Claude Code once). Tokens today: "
                  + Usage.count(root.d.today || 0)
            color: Theme.warn
            font.pixelSize: 13
        }
        Label {
            visible: !!root.d.stale && !!root.d.session
            text: "Values from " + Usage.delta(root.d.age) + " ago (API not reachable)"
            small: true
            color: Theme.warn
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.separator
        }

        Caption { text: "Tokens on this machine" }

        // in · out · cache write · cache read per day
        Column {
            width: parent.width
            spacing: 3
            Repeater {
                model: [{ label: "", head: true }].concat(root.d.days || [])
                delegate: Row {
                    required property var modelData
                    readonly property bool head: !!modelData.head
                    Label {
                        width: 108
                        text: modelData.label
                        font.pixelSize: 12
                        color: Theme.text
                    }
                    Repeater {
                        model: [["in", "in"], ["out", "out"], ["cache w", "cacheWrite"], ["cache r", "cacheRead"]]
                        Label {
                            required property var modelData
                            width: modelData[0].startsWith("cache") ? 66 : 54
                            horizontalAlignment: Text.AlignRight
                            text: parent.head ? modelData[0] : Usage.count(parent.modelData[modelData[1]])
                            font.pixelSize: 12
                            color: parent.head ? Theme.faint : Theme.text
                        }
                    }
                }
            }
        }

        PButton {
            icon: "\u{F03CC}"
            text: "Usage on claude.ai"
            onClicked: {
                Actions.launch(["xdg-open", "https://claude.ai/settings/usage"]);
                root.popup.close();
            }
        }
    }
}
