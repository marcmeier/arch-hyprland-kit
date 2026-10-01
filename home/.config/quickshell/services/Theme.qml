pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The shell's look in one place (the bar, the notifications, the lock screen, the power menu, the
// on-screen display). The two accents come from the wallpaper (theme/apply.py writes
// ~/.config/theme/colors.json) and follow a new one at once; everything else is the kit's fixed
// palette, the same as walker, the login screen and the terminal use.
Singleton {
    id: theme

    property color primary: "#33ccff"   // apply.py's defaults until the file is read
    property color secondary: "#00ff99"
    // the historic names of the stylesheets (theme/colors.css): accent = secondary, accent2 = primary
    readonly property color accent: secondary
    readonly property color accent2: primary

    readonly property color surface: Qt.rgba(20 / 255, 22 / 255, 28 / 255, 0.80)       // the pills
    readonly property color card: Qt.rgba(20 / 255, 22 / 255, 28 / 255, 0.92)          // popups, tooltips
    readonly property color well: Qt.rgba(1, 1, 1, 0.04)                                // a box inside a card
    readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
    readonly property color border: Qt.rgba(1, 1, 1, 0.06)
    readonly property color cardBorder: Qt.rgba(1, 1, 1, 0.10)
    readonly property color separator: Qt.rgba(1, 1, 1, 0.08)
    readonly property color text: "#d7dce2"
    readonly property color dim: "#8b93a1"
    readonly property color faint: Qt.rgba(139 / 255, 147 / 255, 161 / 255, 0.55)
    readonly property color warn: "#ffb454"
    readonly property color crit: "#ff5f6d"
    readonly property color accentInk: "#0b0d10"                                         // text on an accent

    readonly property string font: "JetBrainsMono Nerd Font"

    // the bar: floating pills 36 px high, 6 px below the screen edge (the compact bar is a bit tighter)
    readonly property int barHeight: 36
    readonly property int barGap: 6
    readonly property int barSide: 10
    readonly property int radius: 14
    readonly property int innerRadius: 10

    // the round avatar (apply.py renders it from ~/.face); bumps when it is written again
    readonly property string avatar: Quickshell.env("HOME") + "/.config/theme/avatar.png"
    property int avatarVersion: 0

    function mix(a, b, f) {
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f);
    }
    // a colour between the accents, like the gradient of the active workspace
    function accentAt(f) {
        return mix(primary, secondary, f);
    }
    // ok / warn / crit for a percentage that is running out
    function levelColor(percent) {
        return percent >= 90 ? crit : percent >= 70 ? warn : primary;
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/theme/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (c.primary)
                    theme.primary = c.primary;
                if (c.secondary)
                    theme.secondary = c.secondary;
            } catch (e) {}  // half written: the next change event brings the rest
        }
    }

    FileView {
        path: theme.avatar
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            theme.avatarVersion++;
        }
    }
}
