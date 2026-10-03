pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The shell's look in one place (the bar, the notifications, the power menu, the on-screen display, the
// password dialog). theme/apply.py writes ~/.config/theme/colors.json: the two accents of the wallpaper
// and the named colours of the look that is on, dark or light (theme/scheme.py); the shell follows a
// change at once and blends into it. The lock screen keeps the dark look in both (`night`), like the
// login screen it matches.
Singleton {
    id: theme

    // ---- what colors.json says (apply.py's dark defaults until it is read) ----
    property string scheme: "dark"
    property string appearance: "dark"      // what was chosen: dark, light or auto
    readonly property bool light: scheme === "light"
    property var looks: ({})                // both looks in brief, for the previews in the settings
    property int renders: 0                 // bumps whenever apply.py rendered (a new wallpaper, a new look)

    property color primary: "#33ccff"
    property color secondary: "#00ff99"
    // the historic names of the stylesheets (theme/colors.css): accent = secondary, accent2 = primary
    readonly property color accent: secondary
    readonly property color accent2: primary

    property color glass: "#14161c"          // what the translucent surfaces are made of
    property color overlay: "#ffffff"        // what hovers, wells and borders are made of
    property color shadow: "#000000"
    property color text: "#d7dce2"
    property color dim: "#8b93a1"
    property color strong: "#ffffff"
    property color warn: "#ffb454"
    property color crit: "#ff5f6d"
    property color accentInk: "#0b0d10"      // text on an accent

    // the colours blend into a new look instead of jumping
    readonly property int blend: 420
    Behavior on primary { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on secondary { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on glass { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on overlay { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on shadow { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on text { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on dim { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on strong { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on warn { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on crit { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    Behavior on accentInk { ColorAnimation { duration: theme.blend; easing.type: Easing.InOutQuad } }
    // the strengths differ a little: slate on paper needs less to show than white on night
    property real wellA: 0.04
    property real hoverA: 0.08
    property real borderA: 0.06
    property real cardBorderA: 0.10
    property real trackA: 0.10
    property real surfaceA: 0.80
    property real cardA: 0.92
    Behavior on surfaceA { NumberAnimation { duration: theme.blend } }
    Behavior on cardA { NumberAnimation { duration: theme.blend } }

    // ---- the parts, made of the above ----
    readonly property color surface: Qt.alpha(glass, surfaceA)        // the pills
    readonly property color card: Qt.alpha(glass, cardA)              // popups, tooltips
    readonly property color raised: light ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(40 / 255, 44 / 255, 54 / 255, 0.95)  // a lit tile
    readonly property color well: Qt.alpha(overlay, wellA)            // a box inside a card
    readonly property color hover: Qt.alpha(overlay, hoverA)
    readonly property color border: Qt.alpha(overlay, borderA)
    readonly property color cardBorder: Qt.alpha(overlay, cardBorderA)
    readonly property color separator: Qt.alpha(overlay, 0.08)
    readonly property color track: Qt.alpha(overlay, trackA)          // under a slider, a meter, a switch
    readonly property color faint: Qt.alpha(dim, light ? 0.72 : 0.55)
    readonly property color knob: light ? "#ffffff" : text            // a slider's knob, a switch's off thumb
    readonly property color field: light ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(11 / 255, 13 / 255, 16 / 255, 0.6)
    readonly property color fieldBorder: Qt.alpha(overlay, light ? 0.16 : 0.12)
    readonly property color scrim: light ? Qt.alpha(glass, 0.62) : Qt.rgba(8 / 255, 9 / 255, 12 / 255, 0.6)
    readonly property color dropShadow: Qt.alpha(shadow, light ? 0.18 : 0.45)

    // the lock screen: always the dark look, with the vivid accents (they are made for it)
    readonly property QtObject night: QtObject {
        property color primary: "#33ccff"
        property color secondary: "#00ff99"
        readonly property color text: "#d7dce2"
        readonly property color dim: "#8b93a1"
        readonly property color faint: Qt.rgba(139 / 255, 147 / 255, 161 / 255, 0.55)
        readonly property color warn: "#ffb454"
        readonly property color crit: "#ff5f6d"
        readonly property color card: Qt.rgba(20 / 255, 22 / 255, 28 / 255, 0.78)
        readonly property color field: Qt.rgba(11 / 255, 13 / 255, 16 / 255, 0.6)
        readonly property color fieldBorder: Qt.rgba(215 / 255, 220 / 255, 226 / 255, 0.12)
        function accentAt(f) {
            return theme.mix(primary, secondary, f);
        }
    }

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

    readonly property string applyScript: Quickshell.env("HOME") + "/.config/theme/apply.py"

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

    function apply(c) {
        const k = c.colors || {};
        theme.scheme = c.scheme === "light" ? "light" : "dark";
        theme.appearance = c.appearance || theme.scheme;
        const l = theme.scheme === "light";
        if (c.primary)
            theme.primary = c.primary;
        if (c.secondary)
            theme.secondary = c.secondary;
        if (c.accents) {
            theme.night.primary = c.accents.primary;
            theme.night.secondary = c.accents.secondary;
        } else {
            theme.night.primary = theme.primary;
            theme.night.secondary = theme.secondary;
        }
        theme.glass = k.glass || "#14161c";
        theme.overlay = k.overlay || "#ffffff";
        theme.shadow = k.shadow || "#000000";
        theme.text = k.fg || "#d7dce2";
        theme.dim = k.dim || "#8b93a1";
        theme.strong = k.fg_strong || "#ffffff";
        theme.warn = k.orange || "#ffb454";
        theme.crit = k.red || "#ff5f6d";
        theme.accentInk = k.ink || "#0b0d10";
        theme.wellA = l ? 0.045 : 0.04;
        theme.hoverA = l ? 0.065 : 0.08;
        theme.borderA = l ? 0.07 : 0.06;
        theme.cardBorderA = l ? 0.09 : 0.10;
        theme.trackA = l ? 0.10 : 0.10;
        theme.surfaceA = l ? 0.82 : 0.80;
        theme.cardA = l ? 0.90 : 0.92;
        theme.looks = c.looks || {};
        theme.renders++;
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/theme/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                theme.apply(JSON.parse(text()));
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

    // auto: look at the sun every few minutes; apply.py only renders when it rose or set since
    Process {
        id: sunWatch
        command: ["python3", theme.applyScript, "--follow-sun"]
    }
    Timer {
        interval: 5 * 60 * 1000
        running: theme.appearance === "auto"
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!sunWatch.running)
                sunWatch.running = true;
        }
    }
}
