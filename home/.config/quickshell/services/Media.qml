pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// The player the bar shows: the one you picked in the media popup while it plays (or nothing else
// does), else the first one that plays, else one that is paused. playerctld only mirrors the others.
Singleton {
    id: media

    readonly property var players: Mpris.players.values.filter(p => !p.dbusName.includes("playerctld"))
    property var chosen: null

    readonly property var player: {
        const playing = players.filter(p => p.isPlaying);
        if (chosen && players.includes(chosen) && (chosen.isPlaying || playing.length === 0))
            return chosen;
        if (playing.length)
            return playing[0];
        return players.find(p => p.playbackState === MprisPlaybackState.Paused) || null;
    }
    readonly property bool active: !!player && player.playbackState !== MprisPlaybackState.Stopped
                                   && (player.trackTitle !== "" || player.isPlaying)

    // MPRIS only reports the position on seeks: ask while something plays and someone looks
    property int watchers: 0
    Timer {
        interval: 1000
        repeat: true
        running: media.watchers > 0 && !!media.player && media.player.isPlaying
        onTriggered: media.player.positionChanged()
    }

    function time(seconds) {
        if (!(seconds >= 0) || !isFinite(seconds))
            return "--:--";
        const s = Math.floor(seconds);
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const ss = String(s % 60).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
    }
}
