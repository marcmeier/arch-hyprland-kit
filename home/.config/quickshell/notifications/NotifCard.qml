import QtQuick
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.services
import "../bar"

// One notification: the app's icon (or the picture it sent), the app and when, the summary, the
// text, a progress bar if it sends one, its actions. The same card pops up at the top right and sits
// in the bell's list; `popup` adds the time bar that runs out and the shadow of a floating card.
// Click: the app's default action (or its window) · right click or ×: dismiss · swipe right: dismiss.
Rectangle {
    id: card

    required property int nid
    required property string app
    required property string summary
    required property string body
    required property string icon
    required property string image
    required property int urgency
    required property real progress
    required property string actions
    required property bool clickable
    required property real time

    property bool popup: false
    property bool showApp: true       // the list shows the app once over its group
    required property int timeout     // ms until a popup leaves on its own; 0: it stays
    readonly property bool critical: urgency === NotificationUrgency.Critical
    readonly property bool low: urgency === NotificationUrgency.Low
    readonly property var actionList: { try { return JSON.parse(actions); } catch (e) { return []; } }
    readonly property bool hovered: hover.hovered

    signal expired

    // new content in the same notification (notify-send -r): its time starts again
    onSummaryChanged: if (countdown.running) countdown.restart()
    onBodyChanged: if (countdown.running) countdown.restart()

    implicitWidth: 380
    implicitHeight: content.implicitHeight + 2 * pad
    readonly property int pad: 14
    radius: popup ? 18 : 14
    color: popup ? Theme.card : (mouse.containsMouse ? Qt.alpha(Theme.overlay, 0.06) : Theme.well)
    border.width: popup || critical ? 1 : 0
    border.color: critical ? Qt.alpha(Theme.crit, 0.6) : low ? Theme.cardBorder : Qt.alpha(Theme.primary, 0.45)
    clip: true
    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    HoverHandler {
        id: hover
    }

    // swipe right to dismiss
    property real dragX: 0
    transform: Translate {
        x: card.dragX
    }
    opacity: 1 - Math.min(0.8, Math.max(0, card.dragX) / (card.width * 1.2))
    DragHandler {
        id: swipe
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        onTranslationChanged: card.dragX = Math.max(0, translation.x)
        onActiveChanged: {
            if (active)
                return;
            if (card.dragX > card.width * 0.3)
                Notifs.dismiss(card.nid);
            else
                back.start();
        }
    }
    NumberAnimation {
        id: back
        target: card
        property: "dragX"
        to: 0
        duration: 200
        easing.type: Easing.OutCubic
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: card.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: m => {
            if (m.button === Qt.LeftButton && card.clickable)
                Notifs.activate(card.nid);
            else if (m.button !== Qt.LeftButton || card.popup)
                card.popup ? Notifs.hidePopup(card.nid) : Notifs.dismiss(card.nid);
        }
    }

    Row {
        id: content
        x: card.pad
        y: card.pad
        width: card.width - 2 * card.pad
        spacing: 12

        // the picture it sent, else the app's icon, else a bell
        Item {
            id: art
            width: 40
            height: 40
            readonly property string src: card.image || card.icon

            ClippingRectangle {
                anchors.fill: parent
                visible: art.src !== "" && pic.status === Image.Ready
                radius: 10
                color: "transparent"
                Image {
                    id: pic
                    anchors.fill: parent
                    source: art.src
                    sourceSize: Qt.size(80, 80)
                    fillMode: card.image ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }
            }
            Rectangle {
                anchors.fill: parent
                visible: !(art.src !== "" && pic.status === Image.Ready)
                radius: 10
                color: card.critical ? Qt.alpha(Theme.crit, 0.16) : Qt.alpha(Theme.primary, 0.14)
                // the app's glyph from the bar (services/Apps.qml) when it has one
                readonly property var known: Apps.lookup(card.app)
                Icon {
                    anchors.centerIn: parent
                    size: 20
                    text: card.critical ? "\u{F0028}" : parent.known.glyph !== "\u{F05B2}" ? parent.known.glyph : "\u{F009A}"
                    color: card.critical ? Theme.crit : Theme.primary
                }
            }
        }

        Column {
            width: content.width - art.width - content.spacing
            spacing: 3

            // app · when (the list names the app once over its group)
            Item {
                width: parent.width - 20
                height: 18
                Label {
                    id: appLabel
                    visible: card.showApp
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? Math.min(implicitWidth, parent.width - timeLabel.implicitWidth - 8) : 0
                    elide: Text.ElideRight
                    small: true
                    text: card.app
                    color: card.critical ? Theme.crit : Theme.dim
                    bold: true
                }
                Label {
                    id: timeLabel
                    anchors.left: appLabel.right
                    anchors.leftMargin: card.showApp ? 6 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    small: true
                    color: Theme.faint
                    text: (card.showApp ? "·  " : "") + Notifs.ago(card.time)
                }
            }

            Label {
                width: parent.width
                visible: text !== ""
                text: card.summary
                bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: card.low ? Theme.dim : Theme.text
            }
            Label {
                width: parent.width
                visible: text !== ""
                text: card.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 4 : 6
                elide: Text.ElideRight
                font.pixelSize: 13
                color: Theme.dim
                lineHeight: 1.1
                linkColor: Theme.accent2
            }

            Item {
                visible: card.progress >= 0
                width: parent.width
                height: 14
                PMeter {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    percent: Math.max(0, card.progress)
                    tone: Theme.accent2
                }
            }

            Flow {
                visible: card.actionList.length > 0
                width: parent.width
                topPadding: 6
                spacing: 6
                Repeater {
                    model: card.actionList
                    PButton {
                        required property var modelData
                        required property int index
                        text: modelData.text
                        accent: index === 0 && card.critical
                        implicitHeight: 28
                        onClicked: Notifs.invoke(card.nid, modelData.id)
                    }
                }
            }
        }
    }

    // ×: on hover
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
        width: 24
        height: 24
        radius: 8
        color: closeMouse.containsMouse ? Theme.hover : "transparent"
        opacity: card.hovered ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
        Icon {
            anchors.centerIn: parent
            size: 13
            text: "\u{F0156}"
            color: closeMouse.containsMouse ? Theme.text : Theme.dim
        }
        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifs.dismiss(card.nid)
        }
    }

    // the popup's time running out, in the accent gradient; stops while the pointer is on the card
    Rectangle {
        visible: card.popup && card.timeout > 0
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: card.radius / 2
        height: 2
        radius: 1
        width: (card.width - card.radius) * card.remaining
        opacity: 0.7
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.accent2 }
            GradientStop { position: 1; color: Theme.accent }
        }
    }
    property real remaining: 1
    NumberAnimation on remaining {
        id: countdown
        running: card.popup && card.timeout > 0
        paused: running && (card.hovered || swipe.active)
        from: 1
        to: 0
        duration: Math.max(1, card.timeout)
        onFinished: card.expired()
    }
}
