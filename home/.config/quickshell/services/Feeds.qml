pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// What the bar learns from scripts (everything else comes from Quickshell's own services: Hyprland,
// PipeWire, MPRIS, UPower, NetworkManager, the tray). Each feed runs once for all bars.
// A script that changes something tells the bar with scripts/poke NAME, e.g. "poke sync".
Singleton {
    id: feeds

    readonly property string scripts: Quickshell.shellDir + "/scripts"
    readonly property string home: Quickshell.env("HOME")

    property alias claude: claude
    property alias sync: sync
    property alias weather: weather
    property alias calendar: calendar
    property alias updates: updates
    property alias dictate: dictate
    property string userName: Quickshell.env("USER")

    // SUPER + A and the dictation keep working without the bar; the bar only shows their state
    Feed {
        id: claude
        command: [feeds.scripts + "/claude-usage.py"]
        interval: 180
    }
    Feed {
        id: sync
        command: [feeds.scripts + "/sync.py"]
        interval: 60
    }
    Feed {
        id: weather
        command: [feeds.scripts + "/weather.py"]
        interval: 1800
    }
    Feed {
        id: calendar
        command: [feeds.scripts + "/agenda.py"]
        interval: 60
    }
    Feed {
        id: updates
        command: [feeds.scripts + "/updates.sh"]
        interval: 1800
    }
    Feed {
        id: dictate
        command: [feeds.home + "/.config/hypr/dictate.py", "status"]
    }

    // the full name from the account (chfn), else the login name
    Process {
        running: true
        command: ["getent", "passwd", Quickshell.env("USER")]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = (text.split(":")[4] || "").split(",")[0].trim();
                if (name)
                    feeds.userName = name;
            }
        }
    }

    function refresh(name) {
        const feed = {
            claude: claude, sync: sync, weather: weather, calendar: calendar, updates: updates,
            dictate: dictate
        }[name];
        if (feed)
            feed.refresh();
        return !!feed;
    }

    // run a command, then refresh a feed when it is done (clicks that change what a feed shows)
    function runThen(cmd, name) {
        const p = runner.createObject(feeds, { command: cmd, then: name });
        p.running = true;
    }
    Component {
        id: runner
        Process {
            property string then: ""
            onExited: {
                if (then)
                    feeds.refresh(then);
                destroy();
            }
        }
    }
}
