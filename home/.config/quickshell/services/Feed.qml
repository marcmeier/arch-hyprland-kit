import Quickshell
import Quickshell.Io
import QtQuick

// A script that prints one JSON object, run every `interval` seconds and on refresh() (the bar's IPC:
// scripts/poke NAME). A refresh while it runs starts it once more when it is done.
Item {
    id: feed

    property var command: []
    property int interval: 0          // seconds; 0: only at the start and on refresh()
    property var data: null           // the last answer that parsed
    property bool running: proc.running
    property bool again: false

    function refresh() {
        if (proc.running)
            again = true;
        else
            proc.running = true;
    }

    Process {
        id: proc
        command: feed.command
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (!t)
                    return;
                try {
                    feed.data = JSON.parse(t.split("\n").pop());
                } catch (e) {
                    console.warn("feed", feed.command[0], e);
                }
            }
        }
        onExited: {
            if (feed.again) {
                feed.again = false;
                running = true;
            }
        }
    }

    Timer {
        interval: Math.max(feed.interval, 1) * 1000
        running: feed.interval > 0
        repeat: true
        triggeredOnStart: false
        onTriggered: feed.refresh()
    }

    Component.onCompleted: refresh()
}
