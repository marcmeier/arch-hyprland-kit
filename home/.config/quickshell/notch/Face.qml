import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// The voice assistant's face: a small bot with a screen for a face, rimmed in the wallpaper's accents
// like the active workspace, and an antenna that glows. It listens with wide eyes and a little "o",
// looks up and around while it thinks, talks with the voice's level and smiles when it is done. The
// soft glow behind it is what is left of the old orb.
Item {
    id: face

    property string mode: "idle"     // idle | listening | thinking | answer | error
    property real level: 0           // 0..1, the microphone or the voice
    property bool speaking: false
    property bool reading: false     // the answer is still being typed out: it reads along
    // the pointer over the bubble, in the face's coordinates: it glances at it
    property bool pointerIn: false
    property point pointer: Qt.point(0, 0)
    // the theme's accents (from the wallpaper) and its error colour
    property color primary: "#33ccff"
    property color secondary: "#00ff99"
    property color error: "#ff5f6d"

    implicitWidth: 38
    implicitHeight: 38

    readonly property real u: width / 100
    readonly property bool isError: mode === "error"
    readonly property bool listening: mode === "listening"
    readonly property bool thinking: mode === "thinking"
    readonly property bool answering: mode === "answer"

    property color cA: isError ? error : primary
    property color cB: isError ? Qt.lighter(error, 1.25) : secondary
    Behavior on cA { ColorAnimation { duration: 300 } }
    Behavior on cB { ColorAnimation { duration: 300 } }
    readonly property color screen: "#0c0e13"

    // ---------- time and level ----------
    property real t: 0
    FrameAnimation {
        running: face.visible && face.opacity > 0
        onTriggered: face.t += frameTime
    }
    property real smoothLevel: 0
    Behavior on smoothLevel { NumberAnimation { duration: 90 } }
    onLevelChanged: smoothLevel = level

    // ---------- expression, eased between the modes ----------
    // how far the eyes are open (1 = normal), the crescent of a smile in the eyes, the mouth's curve
    // (-1 frown .. 1 smile), how far it is open and how wide
    property real eyeOpen: isError ? 0.16 : listening ? 1.15 : thinking ? 0.78 : 1
    property real happy: isError ? 0 : answering ? (speaking ? 0.3 : 0.75) : mode === "idle" ? 0.4 : 0
    property real smile: isError ? -0.8 : answering ? 0.85 : thinking ? -0.1 : listening ? 0.1 : 0.5
    property real mouthW: listening ? 0.42 : thinking ? 0.55 : speaking ? 0.85 : 1
    property real mouthShift: thinking ? 0.35 : 0
    property real blush: answering && !speaking ? 0.55 : listening ? 0.2 : 0
    Behavior on eyeOpen { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.005 } }
    Behavior on happy { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    Behavior on smile { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
    Behavior on mouthW { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.005 } }
    Behavior on mouthShift { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on blush { NumberAnimation { duration: 500 } }

    // talking: the voice's level, with a flutter for the syllables; listening: a small curious "o"
    readonly property real open: speaking
        ? Math.min(1, smoothLevel * (0.8 + 0.3 * Math.sin(t * 19)) * 1.15)
        : listening ? 0.28 + smoothLevel * 0.2 : 0

    // ---------- where it looks: -1..1, quick like saccades ----------
    property real gazeX: 0
    property real gazeY: 0
    Behavior on gazeX { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on gazeY { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

    function rnd(a, b) { return a + Math.random() * (b - a); }
    function look() {
        if (pointerIn) {
            const dx = (pointer.x - width / 2) / (width * 3);
            const dy = (pointer.y - height / 2) / (height * 1.5);
            gazeX = Math.max(-1, Math.min(1, dx));
            gazeY = Math.max(-1, Math.min(1, dy));
            glance.interval = 120;
            return;
        }
        if (thinking) {             // up and around
            gazeX = rnd(-0.9, 0.9);
            gazeY = rnd(-1, -0.45);
            glance.interval = rnd(450, 1100);
        } else if (listening) {     // at the user, below the bubble, with small darts
            gazeX = rnd(-0.15, 0.15);
            gazeY = rnd(0.25, 0.45);
            glance.interval = rnd(700, 1600);
        } else if (reading) {       // along the lines of the answer, down to the right
            gazeX = rnd(0.3, 0.9);
            gazeY = rnd(0.45, 0.8);
            glance.interval = rnd(250, 500);
        } else if (speaking) {
            gazeX = rnd(-0.2, 0.2);
            gazeY = rnd(-0.05, 0.25);
            glance.interval = rnd(900, 2000);
        } else if (isError) {
            gazeX = 0;
            gazeY = 0.6;
            glance.interval = 1500;
        } else {                    // now and then a look around
            const away = Math.random() < 0.35;
            gazeX = away ? rnd(-1, 1) : rnd(-0.1, 0.1);
            gazeY = away ? rnd(-0.5, 0.4) : rnd(0, 0.15);
            glance.interval = away ? rnd(500, 900) : rnd(1200, 2600);
        }
    }
    Timer {
        id: glance
        interval: 800
        repeat: true
        running: face.visible && face.opacity > 0
        onTriggered: face.look()
    }
    onModeChanged: {
        look();
        if (isError)
            shake.restart();
    }
    onReadingChanged: look()
    onPointerInChanged: look()
    onPointerChanged: if (pointerIn) look()

    // ---------- blinking ----------
    property real blink: 0
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: face; property: "blink"; to: 1; duration: 60; easing.type: Easing.InQuad }
        NumberAnimation { target: face; property: "blink"; to: 0; duration: 110; easing.type: Easing.OutQuad }
    }
    Timer {
        interval: 3000
        repeat: true
        running: face.visible && face.opacity > 0 && !face.isError
        onTriggered: {
            blinkAnim.restart();
            if (Math.random() < 0.2)           // sometimes twice
                twice.restart();
            interval = face.rnd(2200, 5200);
        }
    }
    Timer { id: twice; interval: 230; onTriggered: blinkAnim.restart() }

    // ---------- head: tilt, bob and a shake on an error ----------
    property real shakeAmp: 0
    NumberAnimation { id: shake; target: face; property: "shakeAmp"; from: 1; to: 0; duration: 900; easing.type: Easing.OutQuad }

    property real tiltBase: listening ? 7 : thinking ? -9 : 0
    Behavior on tiltBase { SpringAnimation { spring: 3; damping: 0.3; epsilon: 0.05 } }
    readonly property real tilt: tiltBase
        + (listening ? 3 * Math.sin(t * 0.7) + smoothLevel * 4 : 0)
        + (thinking ? 3 * Math.sin(t * 1.3) : 0)
        + (speaking ? 2.5 * Math.sin(t * 2.2) * (0.4 + smoothLevel) : 0)
        + shakeAmp * 14 * Math.sin(t * 30)
    readonly property real bob: Math.sin(t * 1.8) * 1.2 * u * (thinking ? 1.6 : 1)
                                - (listening ? smoothLevel * 2.5 * u : 0)

    // ---------- the glow behind (the old orb) ----------
    Item {
        id: aura
        anchors.centerIn: parent
        width: face.width * 1.3
        height: width
        visible: false
        layer.enabled: true
        readonly property real speed: face.thinking ? 2.6 : 0.6
        property real a: 0
        FrameAnimation {
            running: face.visible && face.opacity > 0
            onTriggered: aura.a += frameTime * aura.speed
        }
        Repeater {
            model: 2
            Rectangle {
                required property int index
                width: aura.width * 0.5 * (1 + face.smoothLevel * 0.35)
                height: width
                radius: width / 2
                color: index ? face.cB : face.cA
                x: aura.width / 2 + aura.width * 0.13 * Math.cos(aura.a + index * Math.PI) - width / 2
                y: aura.height / 2 + aura.width * 0.13 * Math.sin(aura.a + index * Math.PI) - height / 2
            }
        }
    }
    MultiEffect {
        source: aura
        anchors.fill: aura
        blurEnabled: true
        blurMax: 24
        blur: 1
        opacity: (face.thinking ? 0.55 : 0.32) + face.smoothLevel * 0.35
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // ---------- the bot ----------
    Item {
        id: body
        width: face.width
        height: face.height
        y: face.bob
        rotation: face.tilt
        transformOrigin: Item.Bottom

        // antenna
        Rectangle {
            x: 50 * face.u - width / 2
            y: 9 * face.u
            width: Math.max(1.2, 3 * face.u)
            height: 14 * face.u
            radius: width / 2
            color: Qt.alpha(face.cA, 0.7)
            rotation: -face.tilt * 0.6 + Math.sin(face.t * 2.4) * 4
            transformOrigin: Item.Bottom
            Rectangle {
                id: tip
                readonly property real glow: face.thinking ? 0.55 + 0.45 * Math.sin(face.t * 7)
                                           : face.listening || face.speaking ? 0.45 + face.smoothLevel * 0.55
                                           : 0.5 + 0.15 * Math.sin(face.t * 1.5)
                anchors.horizontalCenter: parent.horizontalCenter
                y: -height / 2
                width: 12 * face.u * (1 + tip.glow * 0.25)
                height: width
                radius: width / 2
                color: face.cB
                opacity: 0.55 + tip.glow * 0.45
            }
        }

        // the head: an accent rim around a dark screen
        Rectangle {
            id: head
            x: 6 * face.u
            y: 22 * face.u
            width: 88 * face.u
            height: 74 * face.u
            radius: 28 * face.u
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: face.cA }
                GradientStop { position: 1; color: face.cB }
            }

            Rectangle {
                id: screenRect
                anchors.fill: parent
                anchors.margins: Math.max(1.3, 3.5 * face.u)
                radius: head.radius - anchors.margins
                color: face.screen
            }

            // their glow on the screen
            ShaderEffectSource {
                id: featuresTex
                anchors.fill: features
                sourceItem: features
                visible: false
            }
            MultiEffect {
                anchors.fill: features
                source: featuresTex
                blurEnabled: true
                blurMax: 10
                blur: 0.8
                brightness: 0.1
                opacity: 0.65
            }

            // eyes, mouth and cheeks
            Item {
                id: features
                anchors.fill: parent

                readonly property real cx: width / 2 + face.gazeX * 9 * face.u
                readonly property real cy: height * 0.44 + face.gazeY * 7 * face.u

                Repeater {
                    model: 2
                    Item {
                        id: eye
                        required property int index
                        readonly property real side: index ? 1 : -1
                        // the eye on the side it looks to is a little bigger
                        readonly property real near: 1 + 0.08 * face.gazeX * side
                        width: 15 * face.u * near
                        height: 23 * face.u * near * Math.max(0.1, face.eyeOpen * (1 - face.blink))
                        x: features.cx + side * 19 * face.u - width / 2
                        y: features.cy - height / 2
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.lighter(face.cA, 1.15) }
                                GradientStop { position: 1; color: face.cB }
                            }
                        }
                        // a smile from below turns the eye into a crescent
                        Rectangle {
                            width: parent.width * 1.6
                            height: width
                            radius: width / 2
                            x: (parent.width - width) / 2
                            y: parent.height * (1 - face.happy * 0.55)
                            color: face.screen
                        }
                    }
                }

                // cheeks
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        width: 11 * face.u
                        height: 5 * face.u
                        radius: height / 2
                        x: features.cx + (index ? 1 : -1) * 30 * face.u - width / 2
                        y: features.cy + 14 * face.u
                        color: Qt.lighter(face.cA, 1.2)
                        opacity: face.blush * 0.75
                    }
                }

                // the mouth: two curves between the corners, closed it is a line, open a lens
                Shape {
                    id: mouth
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real w: 26 * face.u * face.mouthW
                    readonly property real mx: width / 2 + face.gazeX * 4 * face.u + face.mouthShift * 9 * face.u
                    readonly property real my: height * 0.73 + face.gazeY * 2.5 * face.u
                    readonly property real curve: face.smile * 7 * face.u
                    readonly property real gap: face.open * 15 * face.u
                    ShapePath {
                        strokeWidth: Math.max(1.3, 4 * face.u)
                        strokeColor: Qt.tint(face.cA, Qt.alpha(face.cB, 0.5))
                        fillColor: Qt.tint(face.cA, Qt.alpha(face.cB, 0.5))
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        startX: mouth.mx - mouth.w / 2
                        startY: mouth.my - mouth.curve * 0.3
                        PathQuad {
                            x: mouth.mx + mouth.w / 2
                            y: mouth.my - mouth.curve * 0.3
                            controlX: mouth.mx
                            controlY: mouth.my + mouth.curve - mouth.gap * 0.35
                        }
                        PathQuad {
                            x: mouth.mx - mouth.w / 2
                            y: mouth.my - mouth.curve * 0.3
                            controlX: mouth.mx
                            controlY: mouth.my + mouth.curve + mouth.gap
                        }
                    }
                }
            }

            // a sheen on the screen
            Rectangle {
                x: screenRect.x + screenRect.width * 0.14
                y: screenRect.y + screenRect.height * 0.08
                width: screenRect.width * 0.32
                height: Math.max(1, 4 * face.u)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.10)
            }
        }
    }
}
