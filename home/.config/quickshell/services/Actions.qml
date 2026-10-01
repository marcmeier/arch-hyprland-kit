pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

// What the bar does when you click: Hyprland dispatches and starting programs.
Singleton {
    id: actions

    readonly property string scripts: Quickshell.shellDir + "/scripts"
    readonly property string home: Quickshell.env("HOME")

    // Hyprland 0.56 with a Lua config takes Lua dispatchers ("dispatch workspace N" is rejected there)
    function dispatch(lua, legacy) {
        Hyprland.dispatch(Hyprland.usingLua ? lua : legacy);
    }

    // a workspace number or a relative one ("e+1", "e-1")
    function focusWorkspace(ws) {
        const arg = typeof ws === "number" ? String(ws) : `"${ws}"`;
        dispatch(`hl.dsp.focus({ workspace = ${arg} })`, `workspace ${ws}`);
    }

    // a short command (playerctl, wpctl, systemctl, ...)
    function run(cmd) {
        Quickshell.execDetached(cmd);
    }

    // a program that stays (terminal, menu, mixer): in a scope of its own, so restarting the shell
    // never takes it along
    function launch(cmd) {
        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--"].concat(cmd));
    }

    // a command line in a terminal window
    function terminal(line) {
        launch(["ghostty", "-e", "bash", "-c", line]);
    }

    function script(name, args) {
        launch([scripts + "/" + name].concat(args || []));
    }
}
