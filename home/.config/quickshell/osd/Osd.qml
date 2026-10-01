import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import qs.services
import "../bar"

// The on-screen display: a pill at the bottom of the focused screen when the volume, the speakers'
// or the microphone's mute, the output device or the brightness changes, from the keys, the bar or
// anywhere else (it follows PipeWire itself). Brightness has no service: scripts/brightness tells it.
//   quickshell ipc -p ~/.config/quickshell call osd brightness 40
Scope {
    id: root

    // volume | mic | device | brightness
    property string kind: "volume"
    property real value: 0          // 0..1
    property string text: ""
    property string glyph: ""
    property bool off: false        // muted: the bar and the glyph go dim
    property bool shown: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    // PipeWire reports every level once at the start, and a new device brings its own: no pill for those
    property bool ready: false
    Timer {
        running: true
        interval: 2000
        onTriggered: root.ready = true
    }

    function show(kind, value, text, glyph, off) {
        if (!ready)
            return;
        root.kind = kind;
        root.value = Math.max(0, Math.min(1, value));
        root.text = text;
        root.glyph = glyph;
        root.off = off;
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const target = Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0];
        if (target && win.screen !== target)
            win.screen = target;
        shown = true;
        hide.restart();
    }

    function name(n) {
        return n ? (n.description || n.nickname || n.name) : "";
    }

    function showVolume() {
        const a = sink && sink.audio;
        if (!a)
            return;
        show("volume", a.volume, a.muted ? "muted" : Math.round(a.volume * 100) + "%", Glyphs.volume(a.volume, a.muted, false), a.muted);
    }

    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() {
            if (!switching.running)
                root.showVolume();
        }
        function onMutedChanged() {
            if (!switching.running)
                root.showVolume();
        }
    }
    Connections {
        target: root.source ? root.source.audio : null
        function onMutedChanged() {
            const m = root.source.audio.muted;
            if (!switching.running)
                root.show("mic", 0, m ? "Microphone muted" : "Microphone on", Glyphs.mic(m), m);
        }
    }

    // another output (headphones plugged in, picked in the sound popup): its name
    Timer {
        id: switching
        interval: 800
    }
    onSinkChanged: {
        switching.restart();
        if (sink && sink.audio)
            show("device", sink.audio.volume, name(sink), Glyphs.volume(sink.audio.volume, sink.audio.muted, /headphone|headset/i.test(name(sink))), sink.audio.muted);
        else
            deviceLater.restart();
    }
    // the new device's levels arrive a moment after it
    Timer {
        id: deviceLater
        interval: 300
        onTriggered: {
            const s = root.sink;
            if (s && s.audio)
                root.show("device", s.audio.volume, root.name(s), Glyphs.volume(s.audio.volume, s.audio.muted, /headphone|headset/i.test(root.name(s))), s.audio.muted);
        }
    }
    onSourceChanged: switching.restart()

    IpcHandler {
        target: "osd"

        // percent 0..100 (scripts/brightness after brightnessctl)
        function brightness(percent: int): void {
            const p = Math.max(0, Math.min(100, percent));
            const glyph = p >= 75 ? "\u{F00E0}" : p >= 50 ? "\u{F00DF}" : p >= 25 ? "\u{F00DE}" : "\u{F00DD}";
            root.show("brightness", p / 100, p + "%", glyph, false);
        }
    }

    Timer {
        id: hide
        interval: 1500
        onTriggered: root.shown = false
    }

    PanelWindow {
        id: win

        anchors.bottom: true
        margins.bottom: Math.round((screen ? screen.height : 1080) * 0.08)
        implicitWidth: 340
        implicitHeight: 64
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.shown || pill.opacity > 0.01
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "driftless-osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: pill

            readonly property bool bar: root.kind === "volume" || root.kind === "brightness"
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.shown ? 8 : 20
            width: bar ? 300 : Math.min(parent.width, row.implicitWidth + 36)
            height: 48
            radius: 16
            color: Theme.card
            border.width: 1
            border.color: Theme.cardBorder
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.94

            Behavior on opacity {
                NumberAnimation { duration: root.shown ? 120 : 260 }
            }
            Behavior on y {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on width {
                enabled: pill.opacity > 0.5
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Row {
                id: row
                anchors.verticalCenter: parent.verticalCenter
                x: 16
                spacing: 12

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 18
                    text: root.glyph
                    color: root.off ? (root.kind === "mic" ? Theme.crit : Theme.dim) : Theme.accent2
                }

                // the level, in the accent gradient like the sliders of the popups
                Rectangle {
                    visible: pill.bar
                    anchors.verticalCenter: parent.verticalCenter
                    width: 300 - 32 - 24 - 24 - 46
                    height: 6
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.10)
                    Rectangle {
                        width: Math.max(parent.height, parent.width * root.value)
                        height: parent.height
                        radius: parent.radius
                        opacity: root.off ? 0.35 : 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.accent2 }
                            GradientStop { position: 1; color: Theme.accent }
                        }
                        Behavior on width {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }
                }

                Label {
                    id: valueLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: pill.bar ? 46 : Math.min(metrics.advanceWidth + 2, win.width - 80)
                    TextMetrics {
                        id: metrics
                        font: valueLabel.font
                        text: root.text
                    }
                    horizontalAlignment: pill.bar ? Text.AlignRight : Text.AlignLeft
                    text: root.text
                    elide: Text.ElideRight
                    color: root.off ? Theme.dim : Theme.text
                    font.pixelSize: 13
                }
            }
        }
    }
}
