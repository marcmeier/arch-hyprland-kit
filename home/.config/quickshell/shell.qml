//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.services
import "bar"
import "notch"

// The driftless shell (driftless-shell.service): a bar on every screen with its tooltips and popups,
// and the bubble of "ask Claude by voice" (SUPER + A). One process, one theme from the wallpaper.
// Edits to these files apply on save; scripts tell it about changes with scripts/poke NAME.
ShellRoot {
    Variants {
        id: bars
        model: Quickshell.screens
        Bar {}
    }

    Notch {}

    // Quickshell misses the first workspace change after it starts (the new workspace never shows up):
    // on workspace and monitor events ask Hyprland for the whole state
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["workspacev2", "createworkspacev2", "destroyworkspacev2", "moveworkspacev2", "focusedmon",
                 "renameworkspace", "monitoraddedv2", "monitorremovedv2"].includes(event.name)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            }
        }
    }

    IpcHandler {
        target: "bar"

        // a feed (sync, calendar, updates, notifications, dictate, claude, weather) or "layout"
        function refresh(name: string): bool {
            if (name === "layout") {
                BarLayout.reload();
                return true;
            }
            return Feeds.refresh(name);
        }

        // open or close a popup of the bar on the focused screen: calendar, weather, media, claude,
        // audio, network, battery (e.g. from a key binding)
        function popup(name: string): bool {
            const bar = bars.instances.find(b => b.monitor && b.monitor.focused) || bars.instances[0];
            return !!bar && bar.openNamed(name);
        }
    }
}
