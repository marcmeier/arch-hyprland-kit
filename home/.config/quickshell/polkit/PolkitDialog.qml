import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import QtQuick
import qs.services
import "../bar"

// The password dialog when something asks for more rights (hyprpolkitagent before): installing
// packages from the lists, a mount, an app's settings. The shell is the session's polkit agent; the
// dialog is the lock screen's card over the dimmed focused screen: your picture, what is asked and by
// which action, the password. Enter: authenticate · Esc or "Cancel": no.
// Without the shell there is no agent: polkit then says so to the program that asked.
Scope {
    id: root

    readonly property var flow: agent.flow
    readonly property bool open: agent.isActive && !!flow
    property string password: ""
    property bool checking: false
    property int fails: 0

    PolkitAgent {
        id: agent
    }

    Binding {
        target: Keyboard
        property: "polkitOpen"
        value: root.open
    }

    // a new request: an empty field on the screen you work on
    onOpenChanged: {
        if (!open)
            return;
        password = "";
        checking = false;
        fails = 0;
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const target = Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0];
        if (target && win.screen !== target)
            win.screen = target;
        focusLater.restart();
    }
    Timer {
        id: focusLater
        interval: 50
        onTriggered: field.focusInput()
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        // polkit asks (again, after a wrong password): the field is ready
        function onIsResponseRequiredChanged() {
            if (root.flow.isResponseRequired)
                root.checking = false;
        }
        function onAuthenticationFailed() {
            root.checking = false;
            root.password = "";
            root.fails++;
            shake.restart();
        }
    }

    function submit() {
        if (!flow || checking || !flow.isResponseRequired)
            return;
        checking = true;
        flow.submit(password);
        password = "";
    }
    function cancel() {
        if (flow)
            flow.cancelAuthenticationRequest();
    }

    PanelWindow {
        id: win

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.open || backdrop.opacity > 0.01
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "driftless-polkit"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: Qt.rgba(8 / 255, 9 / 255, 12 / 255, 0.6)
            opacity: root.open ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.open ? 180 : 220; easing.type: Easing.OutCubic }
            }
            // a click beside the card does nothing: a request is answered, not dismissed by accident
            MouseArea {
                anchors.fill: parent
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 520
            height: content.implicitHeight + 64
            radius: 20
            color: Qt.rgba(20 / 255, 22 / 255, 28 / 255, 0.92)
            border.width: 1
            border.color: root.fails > 0 && !root.checking ? Qt.alpha(Theme.crit, 0.45) : Qt.alpha(Theme.primary, 0.25)
            opacity: backdrop.opacity
            scale: 0.96 + 0.04 * backdrop.opacity
            Behavior on border.color {
                ColorAnimation { duration: 200 }
            }

            property real shakeX: 0
            transform: Translate {
                x: card.shakeX
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: card; property: "shakeX"; to: -12; duration: 50 }
                NumberAnimation { target: card; property: "shakeX"; to: 10; duration: 70 }
                NumberAnimation { target: card; property: "shakeX"; to: -6; duration: 70 }
                NumberAnimation { target: card; property: "shakeX"; to: 3; duration: 70 }
                NumberAnimation { target: card; property: "shakeX"; to: 0; duration: 60 }
            }

            Row {
                id: content
                x: 32
                y: 32
                spacing: 28

                Image {
                    id: avatar
                    width: 72
                    height: 72
                    sourceSize: Qt.size(144, 144)
                    source: "file://" + Theme.avatar
                    cache: false
                    smooth: true
                    mipmap: true
                }

                Column {
                    width: card.width - 64 - avatar.width - content.spacing
                    spacing: 10

                    Row {
                        spacing: 8
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{F099D}"
                            size: 16
                            color: Theme.accent2
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Authentication required"
                            bold: true
                            font.pixelSize: 16
                        }
                    }

                    // what is asked, in the program's words
                    Label {
                        width: parent.width
                        text: root.flow ? root.flow.message : ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        color: Theme.dim
                        lineHeight: 1.1
                    }
                    // and by which action, for the careful
                    Label {
                        width: parent.width
                        text: root.flow ? root.flow.actionId : ""
                        elide: Text.ElideMiddle
                        small: true
                        color: Theme.faint
                    }

                    PasswordField {
                        id: field
                        width: parent.width
                        text: root.password
                        checking: root.checking
                        failed: root.fails > 0 && !root.checking && root.password === ""
                        reveal: !!root.flow && root.flow.responseVisible
                        placeholder: root.flow && root.flow.inputPrompt && !/^password:?\s*$/i.test(root.flow.inputPrompt)
                                     ? root.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                        onEdited: t => root.password = t
                        onAccepted: root.submit()
                        onEscaped: root.cancel()
                    }

                    // what polkit adds (a wrong password, a fingerprint prompt), or Caps Lock
                    Label {
                        height: 16
                        width: parent.width
                        elide: Text.ElideRight
                        small: true
                        readonly property string extra: root.flow ? root.flow.supplementaryMessage : ""
                        text: extra !== "" ? extra : root.fails > 0 && !root.checking ? "Wrong password" : Keyboard.caps ? "Caps Lock is on" : ""
                        color: (root.flow && root.flow.supplementaryIsError) || (extra === "" && root.fails > 0) ? Theme.crit
                             : Keyboard.caps && extra === "" ? Theme.warn : Theme.dim
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        PButton {
                            text: "Cancel"
                            onClicked: root.cancel()
                        }
                        PButton {
                            text: "Authenticate"
                            accent: true
                            enabled: root.password !== "" && !root.checking
                            onClicked: root.submit()
                        }
                    }
                }
            }
        }
    }
}
