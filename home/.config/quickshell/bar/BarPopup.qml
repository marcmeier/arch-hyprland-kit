import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// The popup below a bar (calendar, media, audio, ...): one card that opens under the item that was
// clicked and slides over to the next one. A click on the same item, a click anywhere else or Esc
// closes it. Only the card takes input; the rest of the window lets clicks through.
PanelWindow {
    id: win

    property var bar
    property bool open: false
    property string key: ""
    property real anchorX: 0

    screen: bar.screen
    anchors {
        top: true
        left: true
        right: true
    }
    margins.top: bar.implicitHeight + 6
    implicitHeight: Math.round(bar.screen.height * 0.85)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || card.opacity > 0.01
    mask: Region {
        item: card
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "driftless-popup"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    HyprlandFocusGrab {
        windows: [win, win.bar]
        active: win.open && win.visible
        onCleared: win.close()
    }

    function toggle(item, component, k, props) {
        if (open && key === k) {
            close();
            return;
        }
        anchorX = item.mapToItem(null, item.width / 2, 0).x;
        loader.props = props;
        if (loader.sourceComponent === component && loader.item)
            loader.apply();
        else
            loader.sourceComponent = component;
        key = k;
        open = true;
        card.forceActiveFocus();
    }
    function close() {
        open = false;
        key = "";
    }

    // the content goes when the card has faded out
    Timer {
        running: !win.open
        interval: 250
        onTriggered: loader.sourceComponent = null
    }

    Rectangle {
        id: card
        readonly property int pad: 16
        width: (loader.item ? loader.item.implicitWidth : 0) + pad * 2
        height: (loader.item ? loader.item.implicitHeight : 0) + pad * 2
        x: Math.round(Math.max(Theme.barSide, Math.min(win.width - width - Theme.barSide, win.anchorX - width / 2)))
        y: win.open ? 0 : -10
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        transformOrigin: Item.Top
        color: Theme.card
        radius: 18
        border.width: 1
        border.color: Theme.cardBorder
        clip: true
        focus: true
        Keys.onEscapePressed: win.close()

        Behavior on opacity {
            NumberAnimation { duration: win.open ? 150 : 120 }
        }
        Behavior on y {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on x {
            enabled: card.opacity > 0.5
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: card.opacity > 0.5
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: card.opacity > 0.5
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Loader {
            id: loader
            property var props: ({})
            x: card.pad
            y: card.pad

            function apply() {
                if (!item)
                    return;
                if ("popup" in item)
                    item.popup = win;
                if ("bar" in item)
                    item.bar = win.bar;
                for (const k in props)
                    item[k] = props[k];
            }
            onLoaded: apply()
        }
    }
}
