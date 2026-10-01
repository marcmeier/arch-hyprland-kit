pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import QtQuick

// The notification server (org.freedesktop.Notifications; mako's job before). Every notification
// lands in `history` (the bell's popup, grouped by app) and, unless do not disturb holds it, in
// `popups` (the cards at the top right, notifications/Popups.qml) for a few seconds. Both are
// ListModels with a copy of what a card shows, so a card can still fade out after its notification
// is gone. The Notification objects themselves stay in `objects`, for actions and dismissing.
// The list outlives a restart of the shell and a new login: it is kept in
// ~/.local/state/driftless-shell/notifications.json (this machine only, a folder only you can read,
// seven days at most). Kept ones come back without their buttons, the app that sent them is gone.
Singleton {
    id: notifs

    readonly property ListModel popups: ListModel {}
    readonly property ListModel history: ListModel {}
    readonly property int count: history.count
    property alias unread: keep.unread     // new since the list was last open (outlives a reload)
    // do not disturb: notifications go to the list, only critical ones pop up (outlives a reload)
    property alias dnd: keep.dnd
    // the lock screen holds the popups: they come when you are back
    readonly property bool paused: Session.locked
    // the bell's list is open: no cards on top of it (they are in the list)
    property bool listOpen: false
    // a fullscreen window (a game, a video) on the workspace you look at: quiet like do not disturb,
    // and one card afterwards that says how many came in meanwhile
    readonly property bool fullscreen: !!(Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen)
    property var heldInFullscreen: ({})   // id -> true, each one counted once
    // the summary card asks the shell to open the list (shell.qml)
    signal listRequested

    readonly property int maxHistory: 50
    readonly property int maxPopups: 4

    property var objects: ({})       // id -> Notification
    property real now: Date.now()    // for "5 min ago"; ticks while anything shows a time

    Timer {
        interval: 30000
        repeat: true
        running: notifs.count > 0
        onTriggered: notifs.now = Date.now()
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false

        // after a reload the server hands the kept ones over again (lastGeneration): quietly
        onNotification: n => notifs.add(n, n.lastGeneration)
    }

    // The app list is read once now, so the first notification already finds its app's icon.
    Component.onCompleted: void DesktopEntries.applications.values.length

    // ---- kept over a restart ----

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                                       + "/driftless-shell"
    readonly property int keepDays: 7
    property var storedTimes: ({})    // live id -> when it came, from the file (a reload keeps it)
    property int nextStoredId: -100   // kept ones get ids of their own, below the summary card's -1
    property bool restored: false

    FileView {
        id: store
        path: notifs.stateDir + "/notifications.json"
        // read at once: what came before has to be in the list before the server hands anything over
        blockAllReads: true
        preload: false
        atomicWrites: true
        printErrors: false
    }
    // the folder is only yours: what the notifications said stays private
    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p -m 700 "$1" && chmod 700 "$1"', "sh", notifs.stateDir]
    }

    // after the start and after every reload (the token tells which): the live ones the server hands
    // over again keep the time they came, and what the file has beyond them comes back
    function restore() {
        let data = {};
        try {
            data = JSON.parse(store.text() || "{}");
        } catch (e) {}
        const cutoff = Date.now() - keepDays * 86400000;
        const entries = (data.entries || []).filter(e => e && e.time > cutoff);
        const reload = keep.token !== "" && data.token === keep.token;
        if (!keep.token)
            keep.token = Date.now() + "-" + Math.floor(Math.random() * 1e9);

        // the live ones come back from the server right after this (lastGeneration)
        const times = {};
        for (const e of entries) {
            if (reload && e.id > 0)
                times[e.id] = e.time;
        }
        storedTimes = times;
        // the older ones first, so the newest end up on top
        for (const e of entries.slice().reverse()) {
            if (reload && e.id > 0)
                continue;
            addToHistory({
                nid: nextStoredId--, app: e.app || "Notification", summary: e.summary || "", body: e.body || "",
                icon: e.icon || "", image: e.image || "", urgency: e.urgency || 0, progress: -1,
                actions: "[]", clickable: false, timeout: 0, time: e.time
            });
        }
        for (const n of server.trackedNotifications.values)
            add(n, true);
        restored = true;
    }

    function save() {
        const entries = [];
        for (let i = 0; i < history.count; i++) {
            const r = history.get(i);
            entries.push({
                id: r.nid, app: r.app, summary: r.summary, body: r.body, icon: r.icon,
                // a picture handed over in memory does not survive the restart
                image: r.image.startsWith("file://") ? r.image : "", urgency: r.urgency, time: r.time
            });
        }
        store.setText(JSON.stringify({ token: keep.token, entries: entries }) + "\n");
    }
    Timer {
        id: saveLater
        interval: 1500
        onTriggered: notifs.save()
    }
    Connections {
        target: notifs.history
        function onCountChanged() {
            if (notifs.restored)
                saveLater.restart();
        }
        function onDataChanged() {
            if (notifs.restored)
                saveLater.restart();
        }
    }

    // ---- what a card shows ----

    function icon(n) {
        const pick = name => {
            if (!name)
                return "";
            if (name.startsWith("/"))
                return "file://" + name;
            if (name.includes("://"))
                return name;
            return Quickshell.iconPath(name, true);
        };
        // the app's own icon, else its desktop entry's (by the hint or by its name)
        const entry = DesktopEntries.heuristicLookup(n.desktopEntry || n.appName || "");
        return pick(n.appIcon) || pick(entry ? entry.icon : "") || "";
    }

    function image(n) {
        const img = n.image || "";
        return img.startsWith("/") ? "file://" + img : img;
    }

    // value hint 0..100: a progress bar on the card (-1: none)
    function progress(n) {
        const v = n.hints ? n.hints.value : undefined;
        return v === undefined || v === null ? -1 : Math.max(0, Math.min(100, Number(v)));
    }

    // how long a card stays: what the app asks for, else 6 s (low: 3 s); critical ones stay
    function timeout(n) {
        if (n.urgency === NotificationUrgency.Critical)
            return 0;
        if (n.expireTimeout > 0)
            return Math.max(2000, Math.min(60000, n.expireTimeout));   // ms
        return n.urgency === NotificationUrgency.Low ? 3000 : 6000;
    }

    function roles(n, time) {
        return {
            nid: n.id,
            app: n.appName || "Notification",
            summary: n.summary || "",
            body: n.body || "",
            icon: icon(n),
            image: image(n),
            urgency: n.urgency,
            progress: progress(n),
            actions: JSON.stringify((n.actions || []).filter(a => a.identifier !== "default" && a.text)
                                    .map(a => ({ id: a.identifier, text: a.text }))),
            clickable: (n.actions || []).some(a => a.identifier === "default") || !!n.desktopEntry,
            timeout: timeout(n),
            time: time
        };
    }

    // ---- arriving, changing, leaving ----

    function add(n, quiet) {
        if (objects[n.id])
            return;
        n.tracked = true;

        // x-canonical-private-synchronous / x-dunst-stack-tag: the new one replaces the old one with
        // the same tag (notify-send -h string:x-canonical-private-synchronous:NAME)
        const tag = stackTag(n);
        if (tag) {
            for (const id in objects) {
                const old = objects[id];
                if (old && old.appName === n.appName && stackTag(old) === tag)
                    old.dismiss();
            }
        }

        const o = Object.assign({}, objects);
        o[n.id] = n;
        objects = o;

        // a reload hands the live ones over again: they keep the time they came
        const time = quiet && storedTimes[n.id] ? storedTimes[n.id] : Date.now();
        now = Date.now();
        addToHistory(roles(n, time));
        if (!quiet) {
            if (!listOpen)
                unread++;
            popUp(n, roles(n, time));
        }

        const id = n.id;
        n.closed.connect(() => forget(id));
        // replaced in place (same id, notify-send -r): show the new content again
        const changed = () => update(n);
        n.summaryChanged.connect(changed);
        n.bodyChanged.connect(changed);
        n.hintsChanged.connect(changed);
        n.actionsChanged.connect(changed);

        // too many: the oldest go for good
        const extra = [];
        for (let i = maxHistory; i < history.count; i++)
            extra.push(history.get(i).nid);
        extra.forEach(old => dismiss(old));
    }

    function stackTag(n) {
        const h = n.hints || {};
        return h["x-canonical-private-synchronous"] || h["x-dunst-stack-tag"] || "";
    }

    // newest first, an app's notifications together (the list shows one header per app); a new one
    // brings its app's group to the top
    function addToHistory(r) {
        const group = [];
        for (let i = history.count - 1; i >= 0; i--) {
            if (history.get(i).app === r.app)
                group.unshift(i);
        }
        group.forEach((from, k) => {
            if (from !== k)
                history.move(from, k, 1);
        });
        history.insert(0, r);
    }

    // a card unless do not disturb or a fullscreen window holds it (critical ones always come)
    function popUp(n, r) {
        if (n.urgency === NotificationUrgency.Critical)
            showPopup(r);
        else if (dnd)
            return;
        else if (fullscreen)
            heldInFullscreen = Object.assign({}, heldInFullscreen, { [n.id]: true });
        else
            showPopup(r);
    }

    onFullscreenChanged: {
        if (fullscreen)
            return;
        // the ones still there (some were replaced or closed meanwhile)
        const n = Object.keys(heldInFullscreen).filter(id => !!objects[id]).length;
        heldInFullscreen = {};
        if (n === 0)
            return;
        const i = indexIn(popups, -1);
        if (i >= 0)
            popups.remove(i);
        showPopup({
            nid: -1, app: "Notifications", icon: "", image: "", urgency: NotificationUrgency.Normal,
            summary: `${n} notification${n === 1 ? "" : "s"} while you were in fullscreen`, body: "Click: the list", progress: -1,
            actions: "[]", clickable: true, timeout: 8000, time: Date.now()
        });
    }

    function showPopup(r) {
        if (paused) {
            pendingPopups = pendingPopups.filter(p => p.nid !== r.nid).concat([r]);
            return;
        }
        popups.insert(0, r);
        // too many cards: the oldest goes, a critical one only when nothing else is left
        while (popups.count > maxPopups) {
            let i = popups.count - 1;
            while (i > 0 && popups.get(i).urgency === NotificationUrgency.Critical)
                i--;
            popups.remove(i > 0 ? i : popups.count - 1);
        }
    }
    property var pendingPopups: []
    onPausedChanged: {
        if (paused)
            return;
        const waiting = pendingPopups.filter(r => !!objects[r.nid]);
        pendingPopups = [];
        for (const r of waiting.slice(-maxPopups))
            showPopup(r);
    }

    function update(n) {
        const h = indexIn(history, n.id);
        const before = h >= 0 ? history.get(h) : null;
        const r = roles(n, Date.now());
        // the same words again (a reload hands the notification over once more): nothing to show
        const fresh = !before || before.summary !== r.summary || before.body !== r.body || before.progress !== r.progress;
        if (!fresh)
            return;
        for (const model of [history, popups]) {
            const i = indexIn(model, n.id);
            if (i >= 0)
                model.set(i, r);
        }
        if (indexIn(popups, n.id) < 0)
            popUp(n, r);
        now = Date.now();
    }

    function forget(id) {
        hidePopup(id);
        const i = indexIn(history, id);
        if (i >= 0)
            history.remove(i);
        const o = Object.assign({}, objects);
        delete o[id];
        objects = o;
        if (history.count === 0)
            unread = 0;
    }

    function indexIn(model, id) {
        for (let i = 0; i < model.count; i++) {
            if (model.get(i).nid === id)
                return i;
        }
        return -1;
    }

    // ---- what you do with them ----

    // the card's time ran out: it leaves the screen, stays in the list (a transient one goes)
    function hidePopup(id) {
        const i = indexIn(popups, id);
        if (i >= 0)
            popups.remove(i);
        const n = objects[id];
        if (n && n.transient)
            n.expire();
    }

    function dismiss(id) {
        const n = objects[id];
        if (n)
            n.dismiss();
        else
            forget(id);
    }

    function clear() {
        for (const id in objects)
            objects[id].dismiss();
        forgetKept(() => true);
        unread = 0;
    }

    function clearApp(app) {
        for (const id in objects) {
            if ((objects[id].appName || "Notification") === app)
                objects[id].dismiss();
        }
        forgetKept(r => r.app === app);
    }

    // the kept ones (no app behind them any more) that match
    function forgetKept(match) {
        for (let i = history.count - 1; i >= 0; i--) {
            const r = history.get(i);
            if (!objects[r.nid] && r.nid !== -1 && match(r))
                history.remove(i);
        }
    }

    // a click on the card: the app's default action, else its window; then the card goes
    function activate(id) {
        if (id === -1) {
            hidePopup(-1);
            listRequested();
            return;
        }
        const n = objects[id];
        if (!n)
            return;
        const def = (n.actions || []).find(a => a.identifier === "default");
        if (def)
            def.invoke();
        else
            focusApp(n);
        if (!n.resident)
            n.dismiss();
    }

    function invoke(id, identifier) {
        const n = objects[id];
        const action = n ? (n.actions || []).find(a => a.identifier === identifier) : null;
        if (!action)
            return;
        action.invoke();
        if (n && !n.resident)
            n.dismiss();
    }

    // the window of the app that sent it, by its desktop entry or name
    function focusApp(n) {
        const keys = [n.desktopEntry, n.appName].filter(k => !!k).map(k => k.toLowerCase());
        if (!keys.length)
            return;
        const win = Hyprland.toplevels.values.find(t => {
            const cls = ((t.wayland && t.wayland.appId) || (t.lastIpcObject && t.lastIpcObject.class) || "").toLowerCase();
            return cls && keys.some(k => cls === k || cls.endsWith("." + k) || k.endsWith("." + cls));
        });
        if (!win)
            return;
        const address = String(win.address).startsWith("0x") ? win.address : "0x" + win.address;
        Actions.dispatch(`hl.dsp.focus({ window = "address:${address}" })`, `focuswindow address:${address}`);
    }

    function markRead() {
        unread = 0;
    }

    // turned off again: what came in meanwhile waits in the list, not in a flood of cards
    function setDnd(on) {
        dnd = on;
    }

    PersistentProperties {
        id: keep
        reloadableId: "driftless-notifs"
        property bool dnd: false
        property int unread: 0
        // one per run of the shell: the file's token says whether this is a reload or a new start
        property string token: ""
        onLoaded: notifs.restore()
    }

    // "5 min", "14:32", "yesterday 09:10", "12.09."
    function ago(time) {
        const s = Math.max(0, (now - time) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + " min";
        const d = new Date(time);
        const today = new Date(now);
        const hm = Qt.formatTime(d, "hh:mm");
        if (d.toDateString() === today.toDateString())
            return hm;
        const y = new Date(now - 86400000);
        if (d.toDateString() === y.toDateString())
            return "yesterday " + hm;
        return Qt.formatDate(d, "dd.MM.");
    }
}
