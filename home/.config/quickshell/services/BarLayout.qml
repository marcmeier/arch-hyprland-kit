pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Which widgets the bar shows, in which order, and which bar size a screen gets. The same rules as
// scripts/bar_layout.py (the widget manager writes, this reads and follows every change at once):
//   bar.jsonc       the widgets and their default order
//   layout.json     this machine's changes: {"hidden": [...], "order": {variant: {section: [...]}},
//                   "mode": "auto" | "spacious" | "compact"}  (~/.local/state/driftless-shell)
//   host/bar.json   the outputs that get the compact bar in "auto": {"compact": ["eDP-1", "<description>"]}
//                   (default: the notebook panels eDP-1 and eDP-2)
Singleton {
    id: layout

    readonly property var sections: ["modules-left", "modules-center", "modules-right"]
    property var defaults: ({})
    property var saved: ({ hidden: [], order: {} })
    property var narrow: ["eDP-1", "eDP-2"]
    readonly property string mode: ["auto", "spacious", "compact"].includes(saved.mode) ? saved.mode : "auto"

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")

    // JSON with // and /* */ comments and trailing commas, as bar_layout.py reads it
    function parseJsonc(text) {
        const noComments = text.replace(/"(?:\\.|[^"\\])*"|\/\/[^\n]*|\/\*[\s\S]*?\*\//g, m => m.startsWith('"') ? m : "");
        return JSON.parse(noComments.replace(/"(?:\\.|[^"\\])*"|,(?=\s*[}\]])/g, m => m.startsWith('"') ? m : ""));
    }

    function variantFor(screen) {
        if (mode !== "auto")
            return mode;
        const mon = Hyprland.monitors.values.find(m => m.name === screen.name);
        const desc = mon ? mon.description : "";
        return narrow.includes(screen.name) || (desc && narrow.includes(desc)) ? "compact" : "spacious";
    }

    // the members of a group on a variant, hidden ones included
    function allMembers(group, variant) {
        const compact = variant === "compact" && defaults.compact ? defaults.compact[group] : undefined;
        return compact || (defaults.groups && defaults.groups[group]) || [];
    }

    function members(group, variant) {
        const hidden = saved.hidden || [];
        return allMembers(group, variant).filter(m => !hidden.includes(m));
    }

    // {section: [widget, ...]} in the saved order, hidden widgets included (bar_layout.ordered)
    function ordered(variant) {
        const current = {};
        const known = new Set();
        for (const s of sections) {
            current[s] = (defaults[s] || []).slice();
            current[s].forEach(m => known.add(m));
        }
        const keep = (saved.order && saved.order[variant]) || {};
        const result = {};
        const placed = new Set();
        for (const s of sections) {
            result[s] = (keep[s] || []).filter(m => known.has(m) && !placed.has(m));
            result[s].forEach(m => placed.add(m));
        }
        for (const s of sections) {
            current[s].forEach((m, i) => {
                if (placed.has(m))
                    return;
                // next to its neighbour in the defaults, wherever the layout moved that one
                const before = current[s].slice(0, i).reverse().find(p => placed.has(p));
                const where = before ? sections.find(sec => result[sec].includes(before)) : s;
                result[where].splice(before ? result[where].indexOf(before) + 1 : 0, 0, m);
                placed.add(m);
            });
        }
        return result;
    }

    function section(name, variant) {
        const hidden = saved.hidden || [];
        return (ordered(variant)[name] || []).filter(m => !hidden.includes(m));
    }

    function reload() {
        defaultsFile.reload();
        legacy = false;
        Qt.callLater(savedFile.reload);
        hostFile.reload();
    }

    FileView {
        id: defaultsFile
        path: Quickshell.shellDir + "/bar.jsonc"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                layout.defaults = layout.parseJsonc(text());
            } catch (e) {
                console.warn("bar.jsonc:", e);
            }
        }
    }

    // nothing saved yet: the layout from the Waybar days, if there is one (bar_layout.py moves it over)
    property bool legacy: false

    FileView {
        id: savedFile
        path: layout.stateDir + (layout.legacy ? "/waybar/layout.json" : "/driftless-shell/layout.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const l = JSON.parse(text());
                l.hidden = l.hidden || [];
                l.order = l.order || {};
                layout.saved = l;
            } catch (e) {}  // half written: the next change event brings the rest
        }
        onLoadFailed: {
            if (layout.legacy)
                return;
            layout.legacy = true;
            Qt.callLater(reload);  // a new path after a failed read is not read by itself
        }
    }

    FileView {
        id: hostFile
        path: Quickshell.env("HOME") + "/.config/driftless/host/bar.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text()).compact;
                if (Array.isArray(c))
                    layout.narrow = c;
            } catch (e) {}
        }
    }
}
