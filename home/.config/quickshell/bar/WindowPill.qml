import QtQuick
import Quickshell.Hyprland
import qs.services

// The focused window: the app's glyph and the window title (compact: the app's name), from Hyprland.
// Hidden on an empty workspace.
Pill {
    id: pill

    // Hyprland keeps the last window active on an empty workspace: only one on the focused workspace counts
    readonly property var win: {
        const w = Hyprland.activeToplevel;
        const ws = Hyprland.focusedWorkspace;
        return w && (!w.workspace || !ws || w.workspace.id === ws.id) ? w : null;
    }
    readonly property string appId: win ? ((win.wayland && win.wayland.appId) || (win.lastIpcObject && win.lastIpcObject.class) || "") : ""
    readonly property string title: win ? win.title : ""
    readonly property var app: Apps.lookup(appId)
    readonly property string shortTitle: title.replace(/\s+[-—–]\s+(Brave( Origin)?|Mozilla Firefox|Discord|Visual Studio Code)$/, "").trim()

    shown: !!win && appId !== ""

    Seg {
        bar: pill.bar
        interactive: false
        padL: pill.compact ? 8 : 10
        padR: pill.compact ? 10 : 12
        spacing: 8
        tip: [pill.title, pill.appId].filter(x => x).map(Apps.esc).join("<br>")

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.app.glyph
            size: 15
            color: Theme.accent2
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, pill.compact ? 160 : 340)
            elide: Text.ElideRight
            font.weight: Font.DemiBold
            font.pixelSize: pill.compact ? 13 : 14
            text: pill.compact || !pill.shortTitle || pill.shortTitle.toLowerCase() === pill.app.name.toLowerCase()
                  ? pill.app.name : pill.shortTitle
        }
    }
}
