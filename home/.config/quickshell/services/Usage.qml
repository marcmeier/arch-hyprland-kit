pragma Singleton

import Quickshell
import QtQuick

// Formatting for the Claude usage pill and its popup.
Singleton {
    function count(n) {
        return n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e3 ? Math.round(n / 1e3) + "k" : String(n);
    }

    function delta(seconds) {
        seconds = Math.max(Math.floor(seconds || 0), 0);
        const d = Math.floor(seconds / 86400), h = Math.floor(seconds % 86400 / 3600), m = Math.floor(seconds % 3600 / 60);
        return d ? `${d}d ${h}h` : h ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`;
    }

    function resets(limit) {
        if (!limit || !limit.resets)
            return "no active window";
        // the seconds left are from when the script ran: count on from the reset time itself
        const at = new Date(limit.resets);
        const left = (at - new Date()) / 1000;
        if (left <= 0)
            return "reset due";
        return "resets " + Qt.formatDateTime(at, "ddd HH:mm") + "  ·  in " + delta(left);
    }

    function summary(d) {
        if (!d)
            return "";
        const dim = c => `<font color='${Theme.dim}'>${c}</font>`;
        if (!d.session)
            return "<b>Claude Code</b><br>" + dim("Usage API unavailable (login expired? start Claude Code once)");
        return `<b>Session</b> ${d.session.pct}%  ${dim(resets(d.session))}<br><b>Week</b> ${d.week.pct}%  ${dim(resets(d.week))}`
               + (d.stale ? "<br>" + dim(`values from ${delta(d.age)} ago`) : "");
    }
}
