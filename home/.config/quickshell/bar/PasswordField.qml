import QtQuick
import qs.services

// The password field of the lock screen and the polkit dialog: dots in the accent gradient for what
// you typed, three breathing dots while it is checked, red after a wrong one, a Caps Lock warning.
// `text` is what is typed (set it to change the field); `edited(text)` when you type.
Rectangle {
    id: field

    property string text: ""
    property bool checking: false
    property bool failed: false
    property bool reveal: false            // show the text itself (a prompt that is not a password)
    property string placeholder: "Password"
    property bool night: false             // the lock screen: dark in both looks
    readonly property bool focused: input.activeFocus
    signal edited(string text)
    signal accepted
    signal escaped

    function focusInput() {
        input.forceActiveFocus();
    }

    onTextChanged: if (input.text !== text) input.text = text

    implicitWidth: 300
    implicitHeight: 44
    radius: 12
    color: night ? Theme.night.field : Theme.field
    border.width: 1
    border.color: failed ? Qt.alpha(night ? Theme.night.crit : Theme.crit, 0.8)
                : input.activeFocus ? (night ? Theme.night.primary : Theme.primary) : night ? Theme.night.fieldBorder : Theme.fieldBorder
    Behavior on border.color {
        ColorAnimation { duration: 150 }
    }

    TextInput {
        id: input
        anchors.fill: parent
        opacity: 0
        focus: true
        echoMode: TextInput.Password
        cursorVisible: false
        selectByMouse: false
        onTextChanged: if (text !== field.text) field.edited(text)
        Keys.onPressed: e => {
            Keyboard.check();
            if (e.key === Qt.Key_Escape) {
                field.escaped();
                e.accepted = true;
            }
        }
        onAccepted: field.accepted()
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }

    Label {
        anchors.verticalCenter: parent.verticalCenter
        x: 14
        visible: field.text === "" && !field.checking
        text: field.placeholder
        color: field.night ? Theme.night.faint : Theme.faint
    }

    // what you typed, shown (not a password)
    Label {
        anchors.verticalCenter: parent.verticalCenter
        x: 14
        width: parent.width - 50
        elide: Text.ElideLeft
        visible: field.reveal && !field.checking
        text: field.text
        color: field.night ? Theme.night.text : Theme.text
    }

    Row {
        id: dots
        visible: !field.reveal
        anchors.verticalCenter: parent.verticalCenter
        x: 14
        spacing: 6
        opacity: field.checking ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
        readonly property int fit: Math.max(0, Math.floor((field.width - 60) / 14))
        Repeater {
            model: Math.min(field.text.length, dots.fit)
            Rectangle {
                required property int index
                width: 8
                height: 8
                radius: 4
                color: (field.night ? Theme.night : Theme).accentAt(dots.fit > 1 ? index / (dots.fit - 1) : 0)
                scale: 0
                Component.onCompleted: scale = 1
                Behavior on scale {
                    NumberAnimation { duration: 140; easing.type: Easing.OutBack }
                }
            }
        }
    }

    // checking: three dots that breathe in the accents
    Row {
        anchors.centerIn: parent
        spacing: 6
        visible: opacity > 0
        opacity: field.checking ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: 7
                height: 7
                radius: 3.5
                color: (field.night ? Theme.night : Theme).accentAt(index / 2)
                SequentialAnimation on opacity {
                    running: field.checking
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 140 }
                    NumberAnimation { from: 0.2; to: 1; duration: 320 }
                    NumberAnimation { from: 1; to: 0.2; duration: 320 }
                    PauseAnimation { duration: (2 - index) * 140 }
                }
            }
        }
    }

    Icon {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: Keyboard.caps && !field.reveal
        text: "\u{F030E}"
        size: 16
        color: field.night ? Theme.night.warn : Theme.warn
    }
}
