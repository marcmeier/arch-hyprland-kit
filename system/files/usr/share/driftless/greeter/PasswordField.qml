import QtQuick

// The greeter's copy of the shell's password field (home/.config/quickshell/bar/PasswordField.qml; the
// greeter runs as another user and cannot read the home): keep the two in step. The colours come from
// `theme` (shell.qml), Caps Lock from `caps`.
Rectangle {
    id: field

    required property var theme
    property bool caps: false

    property string text: ""
    property bool checking: false
    property bool failed: false
    property bool reveal: false            // show the text itself (a prompt that is not a password)
    property string placeholder: "Password"
    readonly property bool focused: input.activeFocus
    signal edited(string text)
    signal accepted
    signal escaped
    signal keyPressed

    function focusInput() {
        input.forceActiveFocus();
    }

    onTextChanged: if (input.text !== text) input.text = text

    implicitWidth: 300
    implicitHeight: 44
    radius: 12
    color: Qt.rgba(11 / 255, 13 / 255, 16 / 255, 0.6)
    border.width: 1
    border.color: failed ? Qt.alpha(field.theme.crit, 0.8)
                : input.activeFocus ? field.theme.primary : Qt.rgba(215 / 255, 220 / 255, 226 / 255, 0.12)
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
            field.keyPressed();
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

    Text {
        anchors.verticalCenter: parent.verticalCenter
        x: 14
        visible: field.text === "" && !field.checking
        text: field.placeholder
        color: field.theme.faint
        font.family: field.theme.font
        font.pixelSize: 14
        font.weight: Font.Medium
        renderType: Text.NativeRendering
    }

    // what you typed, shown (not a password)
    Text {
        anchors.verticalCenter: parent.verticalCenter
        x: 14
        width: parent.width - 50
        elide: Text.ElideLeft
        visible: field.reveal && !field.checking
        text: field.text
        color: field.theme.text
        font.family: field.theme.font
        font.pixelSize: 14
        font.weight: Font.Medium
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
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
                color: field.theme.accentAt(dots.fit > 1 ? index / (dots.fit - 1) : 0)
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
                color: field.theme.accentAt(index / 2)
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

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: field.caps && !field.reveal
        text: "\u{F030E}"
        font.family: field.theme.font
        font.pixelSize: 16
        color: field.theme.warn
        renderType: Text.NativeRendering
    }
}
