pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Keep awake (the coffee cup in the bar): while on, hypridle neither locks nor turns the screen off.
// It holds an idle lock with logind, which hypridle honours. Not a Wayland IdleInhibitor on the bar:
// Hyprland ignores those on layer surfaces. One process for all screens; it ends with the shell (it
// runs in driftless-shell.service's cgroup). The choice outlives a reload of the shell.
// (Not named "State": QtQuick has a type of that name, which wins.)
Singleton {
    property alias on: keep.on

    PersistentProperties {
        id: keep
        reloadableId: "driftless-keep-awake"
        property bool on: false
    }

    Process {
        running: keep.on
        command: ["systemd-inhibit", "--what=idle", "--who=driftless", "--why=Keep awake (the bar)",
                  "sleep", "infinity"]
    }
}
