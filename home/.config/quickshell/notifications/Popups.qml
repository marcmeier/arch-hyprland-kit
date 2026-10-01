import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.services

// The notification cards at the top right of the focused screen, right below the bar, newest on top
// (four at most). They slide in from the edge, leave after their time (not while the pointer is on
// them) and stay in the bell's list. Do not disturb lets only critical ones through.
//   quickshell ipc -p ~/.config/quickshell call notifications dnd toggle    (on, off, toggle)
//   quickshell ipc -p ~/.config/quickshell call notifications clear
Scope {
    id: root

    // a new card shows on the screen you are working on (the ones still there come along)
    function place() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const target = Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0];
        if (target && win.screen !== target)
            win.screen = target;
    }
    Connections {
        target: Notifs.popups
        function onRowsInserted() {
            root.place();
        }
    }

    IpcHandler {
        target: "notifications"

        // on, off or toggle; answers the state
        function dnd(mode: string): string {
            Notifs.setDnd(mode === "on" ? true : mode === "off" ? false : !Notifs.dnd);
            return Notifs.dnd ? "on" : "off";
        }
        function clear(): void {
            Notifs.clear();
        }
        // "3 (1 new), do not disturb off"
        function state(): string {
            return `${Notifs.count} (${Notifs.unread} new), do not disturb ${Notifs.dnd ? "on" : "off"}`;
        }
    }

    PanelWindow {
        id: win

        anchors {
            top: true
            right: true
        }
        margins.top: Theme.barGap + Theme.barHeight + 8
        margins.right: Theme.barSide
        implicitWidth: 380
        // tall enough for four cards; only the cards take clicks (mask), the rest lets them through
        implicitHeight: Math.round((screen ? screen.height : 1200) * 0.8)
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: (Notifs.popups.count > 0 || list.count > 0 || hideDelay.running) && !Notifs.listOpen
        mask: Region {
            item: list.contentItem
        }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "driftless-notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // the last card's way out still shows
        Timer {
            id: hideDelay
            interval: 400
            running: Notifs.popups.count === 0
        }

        ListView {
            id: list
            anchors.fill: parent
            interactive: false
            spacing: 8
            model: Notifs.popups

            delegate: NotifCard {
                width: ListView.view.width
                popup: true
                onExpired: Notifs.hidePopup(nid)
            }

            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                    NumberAnimation { property: "x"; from: 60; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: 200 }
                    NumberAnimation { property: "x"; to: 80; duration: 240; easing.type: Easing.InCubic }
                }
            }
            // a card that is still coming in when it moves finishes coming in
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; to: 1; duration: 200 }
                NumberAnimation { property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic }
            }
        }
    }
}
