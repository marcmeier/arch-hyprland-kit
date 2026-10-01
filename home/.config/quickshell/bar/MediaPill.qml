import QtQuick
import qs.services

// Now playing (MPRIS): previous · play/pause · next and the title, which slides through when it is
// long (compact: play/pause and the title). Click on the title: cover, progress and the players ·
// wheel: next/previous track · middle: play/pause · right: next track.
Pill {
    id: pill

    readonly property var player: Media.player
    readonly property bool playing: Media.playing
    // fades and folds in and out instead of popping: stays in the bar until it has faded out
    shown: Media.shown || opacity > 0
    opacity: Media.shown ? 1 : 0
    implicitWidth: Media.shown ? row.implicitWidth + padding * 2 : 0

    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    Seg {
        shown: !pill.compact
        bar: pill.bar
        padL: 10
        padR: 2
        tip: "Previous"
        onClicked: if (pill.player) pill.player.previous()
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F04AE}"
            size: 14
            color: parent.parent.hovered ? Theme.text : Theme.dim
        }
    }
    Seg {
        bar: pill.bar
        padL: pill.compact ? 8 : 2
        padR: 2
        tip: pill.playing ? "Pause" : "Play"
        onClicked: if (pill.player) pill.player.togglePlaying()
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.playing ? "\u{F03E4}" : "\u{F040A}"
            size: 18
            color: pill.playing ? Theme.accent2 : Theme.dim
        }
    }
    Seg {
        shown: !pill.compact
        bar: pill.bar
        padL: 2
        padR: 4
        tip: "Next"
        onClicked: if (pill.player) pill.player.next()
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F04AD}"
            size: 14
            color: parent.parent.hovered ? Theme.text : Theme.dim
        }
    }
    Seg {
        id: title
        bar: pill.bar
        padL: 6
        padR: pill.compact ? 10 : 12
        spacing: 8
        tip: {
            const p = pill.player;
            const head = Media.artist ? `<b>${Apps.esc(Media.title)}</b><br>${Apps.esc(Media.artist)}` : `<b>${Apps.esc(Media.title)}</b>`;
            return head + (p && p.trackAlbum ? `<br><font color='${Theme.dim}'>${Apps.esc(p.trackAlbum)}</font>` : "");
        }
        onClicked: button => {
            if (button !== Qt.MiddleButton && button !== Qt.RightButton)
                title.togglePopup();
            else if (pill.player)
                button === Qt.MiddleButton ? pill.player.togglePlaying() : pill.player.next();
        }
        onScrolled: steps => {
            if (pill.player)
                steps < 0 ? pill.player.next() : pill.player.previous();
        }

        popupKey: "media"
        popupComponent: Component {
            MediaPopup {}
        }

        Marquee {
            anchors.verticalCenter: parent.verticalCenter
            text: Media.title
            maxWidth: pill.compact ? 170 : 240
            running: pill.playing
            font.weight: Font.DemiBold
            font.pixelSize: pill.compact ? 13 : 14
            color: pill.playing ? Theme.text : Theme.dim
        }
        Label {
            visible: !pill.compact && text !== ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            width: Math.min(implicitWidth, 140)
            elide: Text.ElideRight
            text: Media.artist
            small: true
            color: Qt.alpha(Theme.text, 0.55)
        }
    }
}
