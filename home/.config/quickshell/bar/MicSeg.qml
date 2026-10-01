import QtQuick
import Quickshell.Services.Pipewire
import qs.services

// The default microphone (PipeWire). Click: mute · wheel: input level.
Seg {
    id: seg

    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool muted: !!(source && source.audio && source.audio.muted)
    readonly property real level: source && source.audio ? source.audio.volume : 0

    PwObjectTracker {
        objects: [seg.source]
    }

    shown: !!source
    padL: 3
    padR: 3
    tip: source ? `Microphone<font color='${Theme.dim}'>  ·  ${muted ? "muted" : Math.round(level * 100) + "%"}</font>`
                  + `<br><font color='${Theme.dim}'>Click: mute  ·  Wheel: level</font>` : ""

    onClicked: if (source && source.audio) source.audio.muted = !source.audio.muted
    onScrolled: steps => {
        if (source && source.audio)
            source.audio.volume = Math.max(0, Math.min(1, Math.round((source.audio.volume + steps * 0.02) * 100) / 100));
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: Glyphs.mic(seg.muted)
        color: seg.muted ? Theme.crit : Theme.dim
    }
}
