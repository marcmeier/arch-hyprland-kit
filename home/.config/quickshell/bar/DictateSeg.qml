import QtQuick
import qs.services

// Dictation (hypr/dictate.py, SUPER + D): ready, recording, transcribing. Click: start/stop · right:
// start/stop without the LLM · middle: cancel the recording.
Seg {
    id: seg

    readonly property string mode: Feeds.dictate.data?.["class"] ?? "idle"
    readonly property string script: Actions.home + "/.config/hypr/dictate.py"

    padL: 3
    padR: 5
    tip: Apps.esc(Feeds.dictate.data?.tooltip ?? "").replace(/\n/g, "<br>")

    onClicked: button => {
        const args = button === Qt.RightButton ? ["toggle", "--raw"] : button === Qt.MiddleButton ? ["cancel"] : ["toggle"];
        Actions.launch([script].concat(args));
    }

    Icon {
        id: icon
        anchors.verticalCenter: parent.verticalCenter
        text: seg.mode === "recording" ? "\u{F0EC2}" : seg.mode === "busy" ? "\u{F01D8}" : "\u{F147D}"
        size: seg.compact ? 16 : 17
        color: seg.mode === "recording" ? Theme.crit : Theme.accent

        // recording: a slow pulse
        SequentialAnimation on opacity {
            running: seg.mode === "recording"
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) icon.opacity = 1
        }
    }
}
