pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Caps Lock, for the password fields (the lock screen, the polkit dialog): read from the keyboards'
// LEDs, since nothing announces it. Checked on every key in a password field and once a second while
// one shows.
Singleton {
    id: keyboard

    property bool caps: false
    // a password field shows (set by the lock screen and the polkit dialog)
    property bool lockOpen: false
    property bool polkitOpen: false

    function check() {
        if (!proc.running)
            proc.running = true;
    }

    Process {
        id: proc
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2> /dev/null"]
        stdout: StdioCollector {
            onStreamFinished: keyboard.caps = text.split("\n").some(l => l.trim() !== "" && l.trim() !== "0")
        }
    }

    Timer {
        running: keyboard.lockOpen || keyboard.polkitOpen
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: keyboard.check()
    }
}
