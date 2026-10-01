import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import qs.services

// The bubble of hypr/notch/notch.py (ask Claude by voice), floating at the top of the screen. notch.py
// drives it over IPC, e.g.:
//   quickshell ipc -p ~/.config/quickshell call notch think "Do I have meetings today?"
// (listening, think, answer, append, error, setLevel, speaking, ringing, hide, state)
Scope {
    id: root

    // idle | listening | thinking | answer | error
    property string mode: "idle"
    property string prompt: ""
    property string fullText: ""
    property int shown: 0
    property real level: -1          // < 0: no real level, the bars move by themselves
    property bool speaking: false    // the answer is being spoken: stay open, the orb pulses with it
    property bool ringing: false     // a timer rings: stay open until it is stopped

    readonly property bool open: mode !== "idle"

    function reset() {
        fullText = "";
        shown = 0;
        level = -1;
    }

    IpcHandler {
        target: "notch"

        function listening(): void {
            root.reset();
            root.prompt = "";
            root.mode = "listening";
        }
        function think(prompt: string): void {
            root.reset();
            root.prompt = prompt;
            root.mode = "thinking";
        }
        function answer(text: string): void {
            root.fullText = text;
            root.shown = 0;
            root.mode = "answer";
        }
        // streaming: add a piece of text
        function append(chunk: string): void {
            if (root.mode !== "answer") {
                root.fullText = "";
                root.shown = 0;
                root.mode = "answer";
            }
            root.fullText += chunk;
        }
        function error(text: string): void {
            root.fullText = text;
            root.shown = 0;
            root.mode = "error";
        }
        function setLevel(l: real): void { root.level = Math.max(0, Math.min(1, l)); }
        function ringing(on: bool): void { root.ringing = on; }
        function speaking(on: bool): void {
            root.speaking = on;
            if (!on) root.level = -1;
        }
        function hide(): void {
            root.speaking = false;
            root.ringing = false;
            root.mode = "idle";
        }
        function state(): string { return root.mode; }
    }

    // typewriter effect
    Timer {
        interval: 16
        repeat: true
        running: root.shown < root.fullText.length
        onTriggered: {
            const rest = root.fullText.length - root.shown;
            root.shown += Math.max(1, Math.ceil(rest / 60));
        }
    }

    // fold away when done (not while the pointer is on it or it still speaks)
    Timer {
        id: autoHide
        interval: root.mode === "error" ? 6000 : 9000 + root.fullText.length * 25
        running: (root.mode === "answer" || root.mode === "error")
                 && root.shown >= root.fullText.length
                 && !hover.hovered
                 && !root.speaking
                 && !root.ringing
        onTriggered: root.mode = "idle"
    }

    PanelWindow {
        id: win

        anchors.top: true
        implicitWidth: 560
        implicitHeight: 360
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "claude-notch"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0

        // only the bubble takes clicks, the rest of the window lets them through
        mask: Region { item: bubble }

        Rectangle {
            id: bubble

            readonly property int pad: 14
            readonly property int headerH: 44
            readonly property int textW: 480 - 2 * pad

            readonly property real targetW: {
                switch (root.mode) {
                case "listening": return 230;
                case "thinking": return Math.min(440, Math.max(250, header.implicitWidth + 2 * pad + 36));
                case "answer":
                case "error": return 480;
                default: return 110;
                }
            }
            readonly property real targetH: {
                if (root.mode === "answer" || root.mode === "error")
                    return headerH + Math.min(measure.implicitHeight, 240) + pad + 4;
                return root.open ? headerH : 26;
            }

            anchors.horizontalCenter: parent.horizontalCenter
            y: root.open ? 6 : -4
            width: targetW
            height: targetH
            radius: Math.min(height / 2, 18)
            color: Theme.card
            border.width: 1
            border.color: root.mode === "error" ? Qt.alpha(Theme.crit, 0.6) : Qt.alpha(Theme.primary, 0.45)
            clip: true

            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.55
            transformOrigin: Item.Top

            // springy bloom
            Behavior on width { SpringAnimation { spring: 4.5; damping: 0.28; epsilon: 0.3 } }
            Behavior on height { SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.3 } }
            Behavior on scale { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.005 } }
            Behavior on y { SpringAnimation { spring: 5; damping: 0.35 } }
            Behavior on opacity { NumberAnimation { duration: root.open ? 140 : 260 } }
            Behavior on border.color { ColorAnimation { duration: 300 } }

            HoverHandler { id: hover }
            // click: close, and stop the recording, Claude or the voice
            TapHandler {
                onTapped: {
                    if (root.mode === "listening" || root.mode === "thinking" || root.speaking || root.ringing)
                        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/notch/notch.py", "cancel"]);
                    root.mode = "idle";
                }
            }

            // ---------- header: orb + status ----------
            Row {
                id: header
                x: bubble.pad - 2
                height: bubble.headerH
                spacing: 10

                Orb {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    mode: root.mode
                    level: root.level < 0 ? 0 : root.level
                    primary: Theme.primary
                    secondary: Theme.secondary
                    error: Theme.crit
                }

                Text {
                    id: status
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, root.mode === "answer" || root.mode === "error" ? 420 : 340)
                    elide: Text.ElideRight
                    color: root.mode === "answer" ? Theme.dim : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    text: {
                        switch (root.mode) {
                        case "listening": return "Listening …";
                        case "thinking": return root.prompt !== "" ? root.prompt : "Thinking …";
                        case "answer": return root.prompt !== "" ? root.prompt : "Claude";
                        case "error": return "Oops";
                        default: return "";
                        }
                    }
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
            }

            // pulsing dots while thinking
            Row {
                anchors.right: parent.right
                anchors.rightMargin: bubble.pad + 2
                y: (bubble.headerH - height) / 2
                spacing: 4
                visible: opacity > 0
                opacity: root.mode === "thinking" && root.prompt !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 5; height: 5; radius: 2.5
                        color: Theme.accentAt(index / 2)
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 160 }
                            NumberAnimation { from: 0.2; to: 1; duration: 380 }
                            NumberAnimation { from: 1; to: 0.2; duration: 380 }
                            PauseAnimation { duration: (2 - index) * 160 }
                        }
                    }
                }
            }

            // level bars while listening
            Row {
                id: bars
                anchors.right: parent.right
                anchors.rightMargin: bubble.pad + 2
                height: 24
                y: (bubble.headerH - height) / 2
                spacing: 3
                visible: opacity > 0
                opacity: root.mode === "listening" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                property real t: 0
                FrameAnimation {
                    running: bars.visible
                    onTriggered: bars.t += frameTime
                }

                Repeater {
                    model: 6
                    Rectangle {
                        required property int index
                        readonly property real fake: 0.35 + 0.3 * Math.sin(bars.t * (5 + index * 1.3) + index)
                                                         + 0.2 * Math.sin(bars.t * 2.1 + index * 2)
                        readonly property real lvl: root.level < 0
                            ? fake
                            : root.level * (0.55 + 0.45 * Math.abs(Math.sin(bars.t * 7 + index * 1.7)))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 4 + 20 * Math.max(0, Math.min(1, lvl))
                        radius: 1.5
                        color: Theme.accentAt(index / 5)
                        Behavior on height { NumberAnimation { duration: 70 } }
                    }
                }
            }

            // ---------- answer ----------
            Text {
                id: measure
                visible: false
                width: bubble.textW
                wrapMode: Text.Wrap
                font: answerText.font
                lineHeight: 1.15
                text: root.fullText
                textFormat: Text.PlainText
            }

            Text {
                id: answerText
                x: bubble.pad
                y: bubble.headerH - 2
                width: bubble.textW
                height: Math.min(measure.implicitHeight, 240)
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: root.mode === "error" ? Qt.lighter(Theme.crit, 1.35) : Theme.text
                font.family: Theme.font
                font.pixelSize: 14
                lineHeight: 1.15
                text: root.fullText.substring(0, root.shown)
                opacity: (root.mode === "answer" || root.mode === "error") ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
        }
    }
}
