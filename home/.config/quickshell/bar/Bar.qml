import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// One bar per screen: floating pills in three sections. Which widgets, in which order, and whether
// the screen gets the compact bar comes from BarLayout (bar.jsonc and this machine's layout.json).
// Each bar has its own tooltip and popup window right below it.
PanelWindow {
    id: bar

    required property var modelData
    screen: modelData
    readonly property string variant: BarLayout.variantFor(modelData)
    readonly property bool compact: variant === "compact"
    readonly property var monitor: Hyprland.monitors.values.find(m => m.name === modelData.name) ?? null

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barGap + Theme.barHeight
    exclusiveZone: implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "driftless-bar"
    WlrLayershell.layer: WlrLayer.Top

    // keep awake (the coffee cup in the system pill)
    IdleInhibitor {
        window: bar
        enabled: !!State.idleInhibited
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: Theme.barGap
        anchors.leftMargin: Theme.barSide
        anchors.rightMargin: Theme.barSide

        Section {
            name: "modules-left"
            anchors.left: parent.left
        }
        Section {
            name: "modules-center"
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Section {
            name: "modules-right"
            anchors.right: parent.right
        }
    }

    component Section: Row {
        id: section
        property string name
        height: Theme.barHeight
        spacing: bar.compact ? 6 : 8

        Repeater {
            model: BarLayout.section(section.name, bar.variant)
            delegate: Loader {
                required property string modelData
                sourceComponent: bar.widget(modelData)
                visible: !!(item && item.shown)
                onLoaded: item.bar = bar
            }
        }
    }

    // ---- the widgets by their names in bar.jsonc ----

    function widget(name) {
        return ({
            "group/user": userPill,
            "group/workspaces": workspaces,
            "custom/window": windowPill,
            "group/datetime": dateTime,
            "group/media": mediaPill,
            "group/claude": claudeGroup,
            "group/tray": trayGroup,
            "custom/ask": askSeg,
            "custom/claude": claudeSeg,
            "group/status": statusPill,
            "group/system": systemPill,
            "clock": clockSeg,
            "custom/weather": weatherSeg,
            "custom/calendar": eventSeg,
            "network": networkSeg,
            "bluetooth": bluetoothSeg,
            "pulseaudio": volumeSeg,
            "pulseaudio#mic": micSeg,
            "custom/dictate": dictateSeg,
            "battery": batterySeg,
            "tray": traySeg,
            "custom/updates": updatesSeg,
            "custom/sync": syncSeg,
            "idle_inhibitor": idleSeg,
            "custom/notifications": notifySeg,
            "custom/power": powerSeg
        })[name] || null;
    }

    Component { id: userPill; UserPill {} }
    Component { id: workspaces; Workspaces {} }
    Component { id: windowPill; WindowPill {} }
    Component { id: dateTime; GroupPill { name: "group/datetime"; separators: true } }
    Component { id: mediaPill; MediaPill {} }
    Component { id: claudeGroup; GroupPill { name: "group/claude" } }
    Component { id: trayGroup; GroupPill { name: "group/tray" } }
    Component { id: askSeg; AskSeg {} }
    Component { id: claudeSeg; ClaudeSeg {} }
    Component { id: statusPill; GroupPill { name: "group/status" } }
    Component { id: systemPill; GroupPill { name: "group/system" } }
    Component { id: clockSeg; ClockSeg {} }
    Component { id: weatherSeg; WeatherSeg {} }
    Component { id: eventSeg; EventSeg {} }
    Component { id: networkSeg; NetworkSeg {} }
    Component { id: bluetoothSeg; BluetoothSeg {} }
    Component { id: volumeSeg; VolumeSeg {} }
    Component { id: micSeg; MicSeg {} }
    Component { id: dictateSeg; DictateSeg {} }
    Component { id: batterySeg; BatterySeg {} }
    Component { id: traySeg; TraySeg {} }
    Component { id: updatesSeg; UpdatesSeg {} }
    Component { id: syncSeg; SyncSeg {} }
    Component { id: idleSeg; IdleSeg {} }
    Component { id: notifySeg; NotifySeg {} }
    Component { id: powerSeg; PowerSeg {} }

    // ---- tooltips and popups ----

    BarTooltip {
        id: tooltip
        bar: bar
    }
    BarPopup {
        id: popup
        bar: bar
    }

    // text: a function that returns rich text (read again while it shows)
    function showTip(item, text) {
        if (!popup.open)
            tooltip.show(item, text);
    }
    function hideTip(item) {
        tooltip.hide(item);
    }
    function togglePopup(item, component, key, props) {
        tooltip.hide(null);
        popup.toggle(item, component, key, props || {});
    }
    function closePopup() {
        popup.close();
    }

    // the parts that open a popup, by its name, for the IPC ("popup calendar")
    property var popupOwners: ({})
    function registerPopup(key, item) {
        popupOwners[key] = item;
    }
    function openNamed(key) {
        const item = popupOwners[key];
        if (!item || !item.visible)
            return false;
        item.togglePopup();
        return true;
    }
}
