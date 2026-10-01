import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The month with a dot on every day that has events, and the events coming up (khal). Click a day:
// its events · arrows or wheel: other months · "Open calendar": ikhal, where you add and edit them.
Item {
    id: root

    property var popup
    property var bar

    readonly property var today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()          // 0..11
    property var eventDays: []
    property var picked: null                     // {date, label, sub, events} of a clicked day
    readonly property bool isThisMonth: year === today.getFullYear() && month === today.getMonth()
    readonly property var agenda: Feeds.calendar.data ? Feeds.calendar.data.agenda : []
    // what comes up, at most `max` events
    function upcoming(max) {
        const out = [];
        let left = max;
        for (const day of agenda) {
            if (left <= 0)
                break;
            const events = day.events.slice(0, left);
            left -= events.length;
            out.push(Object.assign({}, day, { events: events }));
        }
        return out;
    }
    readonly property int cell: 38

    implicitWidth: cell * 7
    implicitHeight: column.implicitHeight

    function shift(n) {
        const d = new Date(year, month + n, 1);
        year = d.getFullYear();
        month = d.getMonth();
        picked = null;
    }
    function iso(d) {
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    }

    onYearChanged: monthProc.running = true
    onMonthChanged: monthProc.running = true

    Process {
        id: monthProc
        running: true
        command: [Actions.scripts + "/agenda.py", "month", `${root.year}-${String(root.month + 1).padStart(2, "0")}`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.eventDays = JSON.parse(text).days;
                } catch (e) {}
            }
        }
    }
    Process {
        id: dayProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.picked = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 10

        // ---- month and the arrows ----
        Item {
            width: parent.width
            height: 32

            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: 4
                text: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM yyyy")
                bold: true
                font.pixelSize: 15
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                PButton {
                    visible: !root.isThisMonth
                    text: "Today"
                    flat: true
                    onClicked: {
                        root.year = root.today.getFullYear();
                        root.month = root.today.getMonth();
                        root.picked = null;
                    }
                }
                PButton {
                    icon: "\u{F0141}"
                    flat: true
                    onClicked: root.shift(-1)
                }
                PButton {
                    icon: "\u{F0142}"
                    flat: true
                    onClicked: root.shift(1)
                }
            }
        }

        // ---- the grid, Monday first ----
        Item {
            width: parent.width
            height: grid.height + weekdays.height

            WheelHandler {
                onWheel: e => root.shift(e.angleDelta.y > 0 ? -1 : 1)
            }

            Row {
                id: weekdays
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    Label {
                        required property string modelData
                        required property int index
                        width: root.cell
                        height: 22
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        small: true
                        color: index >= 5 ? Qt.alpha(Theme.accent2, 0.7) : Theme.faint
                    }
                }
            }

            Grid {
                id: grid
                y: weekdays.height
                columns: 7

                Repeater {
                    model: 42
                    delegate: Item {
                        id: day
                        required property int index
                        readonly property var first: new Date(root.year, root.month, 1)
                        readonly property int lead: (first.getDay() + 6) % 7
                        readonly property var date: new Date(root.year, root.month, 1 + index - lead)
                        readonly property bool inMonth: date.getMonth() === root.month
                        readonly property bool isToday: root.iso(date) === root.iso(root.today)
                        readonly property bool isPicked: !!root.picked && root.picked.date === root.iso(date)
                        readonly property bool hasEvents: inMonth && root.eventDays.includes(date.getDate())
                        // the sixth row only when the month needs it
                        visible: index < 35 || lead + new Date(root.year, root.month + 1, 0).getDate() > 35

                        width: root.cell
                        height: 34

                        Rectangle {
                            anchors.centerIn: parent
                            width: 32
                            height: 30
                            radius: 9
                            visible: day.isToday || day.isPicked || mouse.containsMouse
                            color: day.isToday ? "transparent" : mouse.containsMouse && !day.isPicked ? Theme.hover : Qt.alpha(Theme.accent2, 0.18)
                            border.width: day.isPicked && !day.isToday ? 1 : 0
                            border.color: Qt.alpha(Theme.accent2, 0.6)
                            gradient: day.isToday ? todayGradient : null
                        }
                        Label {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: day.hasEvents ? -3 : 0
                            text: day.date.getDate()
                            font.pixelSize: 13
                            bold: day.isToday
                            color: day.isToday ? Theme.accentInk : !day.inMonth ? Qt.alpha(Theme.dim, 0.4)
                                 : day.index % 7 >= 5 ? Qt.lighter(Theme.dim, 1.15) : Theme.text
                        }
                        Rectangle {
                            visible: day.hasEvents
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height / 2 + 6
                            width: 4
                            height: 4
                            radius: 2
                            color: day.isToday ? Theme.accentInk : Theme.accent
                        }
                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (day.isPicked) {
                                    root.picked = null;
                                    return;
                                }
                                dayProc.command = [Actions.scripts + "/agenda.py", "day", root.iso(day.date)];
                                dayProc.running = true;
                            }
                        }
                    }
                }
            }
            Gradient {
                id: todayGradient
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accent2 }
                GradientStop { position: 1; color: Theme.accent }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.separator
        }

        // ---- a clicked day, or what comes up ----
        Caption {
            x: 4
            text: root.picked ? root.picked.label + "  ·  " + root.picked.sub : "Coming up"
        }

        Column {
            width: parent.width
            spacing: 8

            Label {
                visible: root.picked ? root.picked.events.length === 0 : root.agenda.length === 0
                x: 4
                text: root.picked ? "Nothing on this day" : "No events in the next days"
                dim: true
                font.pixelSize: 13
            }

            Repeater {
                model: root.picked ? [root.picked] : root.upcoming(7)
                delegate: Column {
                    required property var modelData
                    width: parent.width
                    spacing: 4

                    Label {
                        visible: !root.picked
                        x: 4
                        text: modelData.label + "  " + modelData.sub
                        small: true
                        dim: true
                    }
                    Repeater {
                        model: modelData.events
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 30
                            radius: 8
                            color: Theme.well
                            Rectangle {
                                x: 0
                                width: 3
                                height: parent.height - 12
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 2
                                color: Theme.accent2
                            }
                            Label {
                                id: time
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 62
                                text: modelData.allDay ? "all day" : modelData.continued ? "→ " + modelData.end : modelData.start
                                small: true
                                color: Theme.accent2
                            }
                            Label {
                                anchors.left: time.right
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: modelData.title
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }
        }

        Label {
            visible: !!(Feeds.calendar.data && Feeds.calendar.data.error)
            width: parent.width
            wrapMode: Text.Wrap
            text: "⚠ " + (Feeds.calendar.data ? Feeds.calendar.data.error : "")
            color: Theme.warn
            small: true
        }

        Row {
            spacing: 8
            PButton {
                icon: "\u{F00ED}"
                text: "Open calendar"
                accent: true
                onClicked: {
                    Actions.script("ikhal.sh");
                    root.popup.close();
                }
            }
            PButton {
                icon: "\u{F0450}"
                text: "Sync"
                onClicked: Feeds.runThen([Actions.scripts + "/calendar-sync.sh"], "calendar")
            }
        }
    }
}
