import QtQuick
import Quickshell.Services.Pipewire
import qs.services

// The default output (PipeWire). Wheel: volume · click: outputs, inputs and their levels · middle:
// the mixer · right: mute.
Seg {
    id: seg

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: !!(sink && sink.audio && sink.audio.muted)
    readonly property real level: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool headphones: !!sink && /headphone|headset/i.test((sink.properties || {})["device.form-factor"] || sink.description || "")

    PwObjectTracker {
        objects: [seg.sink]
    }

    shown: !!sink
    padL: compact ? 6 : 6
    padR: compact ? 6 : 8
    spacing: 6
    tip: sink ? `${Apps.esc(sink.description || sink.name)}<font color='${Theme.dim}'>  ·  ${muted ? "muted" : Math.round(level * 100) + "%"}</font>`
                + `<br><font color='${Theme.dim}'>Click: outputs  ·  Middle: mixer  ·  Right: mute</font>` : ""

    onClicked: button => {
        if (button === Qt.RightButton)
            sink.audio.muted = !sink.audio.muted;
        else if (button === Qt.MiddleButton)
            Actions.launch(["pwvucontrol"]);
        else
            togglePopup();
    }
    onScrolled: steps => {
        if (sink && sink.audio)
            sink.audio.volume = Math.max(0, Math.min(1, Math.round((sink.audio.volume + steps * 0.02) * 100) / 100));
    }

    popupKey: "audio"
    popupComponent: Component {
        AudioPopup {}
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: Glyphs.volume(seg.level, seg.muted, seg.headphones)
        color: seg.muted ? Theme.dim : Theme.text
    }
    Label {
        visible: !seg.compact
        anchors.verticalCenter: parent.verticalCenter
        text: seg.muted ? "muted" : Math.round(seg.level * 100) + "%"
        color: seg.muted ? Theme.dim : Theme.text
    }
}
