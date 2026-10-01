import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Effects
import qs.services
import "../bar"

// One screen of the lock (lock/Lock.qml): the login screen's look. Every screen takes the password,
// so typing works wherever the pointer is; what you type shows on all of them.
WlSessionLockSurface {
    id: surface

    required property var lockScope
    readonly property var ctx: lockScope

    color: "black"

    // the login screen's background (theme/apply.py: blurred and darkened like the greeter's), or the
    // wallpaper blurred here when it is missing
    Image {
        id: login
        anchors.fill: parent
        source: "file://" + Quickshell.env("HOME") + "/.cache/theme/login.png"
        fillMode: Image.PreserveAspectCrop
        // at once: a new surface (a reload, a new screen) must not show black first
        asynchronous: false
        cache: false
    }
    Image {
        id: wall
        anchors.fill: parent
        visible: false
        source: login.status === Image.Error ? "file://" + Quickshell.env("HOME") + "/.config/wall.png" : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    MultiEffect {
        anchors.fill: parent
        visible: login.status === Image.Error && wall.status === Image.Ready
        source: wall
        blurEnabled: true
        blur: 1
        blurMax: 64
        brightness: -0.45
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: surface.ctx.unlocking ? 0 : 1
        scale: surface.ctx.unlocking ? 1.03 : 1
        Behavior on opacity {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }

        // ---- the clock, big and light like the login screen's ----
        Column {
            id: clockBox
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.5) - 290
            spacing: 4

            Text {
                id: clock
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.font
                font.pixelSize: 96
                font.weight: Font.ExtraLight
                color: Theme.text
                text: Qt.formatTime(time.date, "hh:mm")
                renderType: Text.NativeRendering
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.45)
                    shadowBlur: 0.8
                    shadowVerticalOffset: 4
                }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 17
                color: Theme.dim
                text: Qt.locale().toString(time.date, "dddd, d. MMMM")
            }
        }
        SystemClock {
            id: time
            precision: SystemClock.Minutes
        }

        // ---- the card: your picture, your name, the password ----
        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.5) - 40
            width: 480
            height: 168
            radius: 20
            color: Qt.rgba(20 / 255, 22 / 255, 28 / 255, 0.78)
            border.width: 1
            border.color: surface.ctx.failed ? Qt.alpha(Theme.crit, 0.45) : Qt.alpha(Theme.primary, 0.25)
            Behavior on border.color {
                ColorAnimation { duration: 200 }
            }

            // a wrong password shakes it
            property real shake: 0
            transform: Translate {
                x: card.shake
            }
            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: card; property: "shake"; to: -12; duration: 50 }
                NumberAnimation { target: card; property: "shake"; to: 10; duration: 70 }
                NumberAnimation { target: card; property: "shake"; to: -6; duration: 70 }
                NumberAnimation { target: card; property: "shake"; to: 3; duration: 70 }
                NumberAnimation { target: card; property: "shake"; to: 0; duration: 60 }
            }
            Connections {
                target: surface.ctx
                function onFailsChanged() {
                    if (surface.ctx.fails > 0)
                        shakeAnim.restart();
                }
            }

            Image {
                id: avatar
                x: 32
                anchors.verticalCenter: parent.verticalCenter
                width: 96
                height: 96
                sourceSize: Qt.size(192, 192)
                source: "file://" + Theme.avatar
                cache: false
                smooth: true
                mipmap: true
            }

            Column {
                x: avatar.x + avatar.width + 28
                anchors.verticalCenter: parent.verticalCenter
                width: card.width - x - 32
                spacing: 10

                Label {
                    text: Feeds.userName
                    font.pixelSize: 17
                    bold: true
                    color: Theme.dim
                }

                PasswordField {
                    id: field
                    width: parent.width
                    text: surface.ctx.password
                    checking: surface.ctx.checking
                    failed: surface.ctx.failed
                    onEdited: t => {
                        surface.ctx.password = t;
                        if (t !== "")
                            surface.ctx.failed = false;
                    }
                    onAccepted: surface.ctx.submit()
                    onEscaped: surface.ctx.password = ""
                }

                // why it did not open, Caps Lock, or what PAM asks
                Label {
                    height: 16
                    small: true
                    text: surface.ctx.message !== "" ? surface.ctx.message : Keyboard.caps ? "Caps Lock is on" : ""
                    color: surface.ctx.failed ? Theme.crit : Keyboard.caps ? Theme.warn : Theme.dim
                }
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: field.focusInput()
            }
        }

        // ---- at the bottom: what waits, quietly (no notification text on a locked screen) ----
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 36
            spacing: 22

            readonly property var bat: UPower.displayDevice
            readonly property bool hasBat: !!bat && bat.isLaptopBattery && bat.isPresent

            Row {
                visible: parent.hasBat
                spacing: 6
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.hasBat ? Glyphs.battery(Math.round(parent.parent.bat.percentage * 100), parent.parent.bat.state === UPowerDeviceState.Charging) : ""
                    color: Theme.dim
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    small: true
                    dim: true
                    text: parent.parent.hasBat ? Math.round(parent.parent.bat.percentage * 100) + "%" : ""
                }
            }
            Row {
                visible: Notifs.count > 0
                spacing: 6
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Notifs.dnd ? "\u{F009B}" : "\u{F009E}"
                    color: Theme.dim
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    small: true
                    dim: true
                    text: Notifs.count + (Notifs.count === 1 ? " notification" : " notifications")
                }
            }
        }
    }

    Component.onCompleted: field.focusInput()
}
