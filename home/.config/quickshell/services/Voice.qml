pragma Singleton

import Quickshell
import QtQuick

// "Ask Claude by voice" between the bubble (notch/Notch.qml) and the button in the bar (bar/AskSeg.qml):
// the bubble's state for the button, and where the button is, so the bubble grows out of it.
Singleton {
    id: voice

    // idle | listening | thinking | answer | error (set by the bubble)
    property string mode: "idle"
    property bool speaking: false

    // the ask button of each screen's bar, by screen name
    property var buttons: ({})

    function register(screenName, item) {
        const b = Object.assign({}, buttons);
        b[screenName] = item;
        buttons = b;
    }

    // the button's centre in its bar (x), or -1 when that bar has none showing
    function anchorX(screenName) {
        const item = buttons[screenName];
        if (!item || !item.visible || !item.width)
            return -1;
        return item.mapToItem(null, item.width / 2, 0).x;
    }
}
