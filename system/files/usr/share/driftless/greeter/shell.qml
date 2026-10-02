import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import QtQuick
import QtQuick.Effects

// The login screen: the lock screen's look (home/.config/quickshell/lock/LockSurface.qml), so logging
// in and unlocking are one thing. Started by /usr/lib/driftless/greeter in cage as the user "greeter",
// which cannot read any home: everything it shows comes from /var/lib/driftless/greeter, rendered by
// greeter-update (login.png, avatar.png, colors.json, user), or from the system (the accounts, the
// sessions in /usr/share/wayland-sessions, /etc/hostname).
// DRIFTLESS_GREETER_DIR=~/.cache/theme quickshell -p /usr/share/driftless/greeter previews it in a
// window of the running session (no greetd there: the password is never checked);
// DRIFTLESS_GREETER_USER=NAME shows that account instead of the real ones (screenshots).
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("DRIFTLESS_GREETER_DIR") || "/var/lib/driftless/greeter"
    readonly property bool preview: !Greetd.available

    // ---- the look: the shell's fixed palette (services/Theme.qml) and this machine's two accents ----
    QtObject {
        id: look
        property color primary: "#33ccff"
        property color secondary: "#00ff99"
        readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
        readonly property color text: "#d7dce2"
        readonly property color dim: "#8b93a1"
        readonly property color faint: Qt.rgba(139 / 255, 147 / 255, 161 / 255, 0.55)
        readonly property color warn: "#ffb454"
        readonly property color crit: "#ff5f6d"
        readonly property string font: "JetBrainsMono Nerd Font"

        function mix(a, b, f) {
            return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f);
        }
        function accentAt(f) {
            return mix(primary, secondary, f);
        }
    }
    FileView {
        path: root.dir + "/colors.json"
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (c.primary)
                    look.primary = c.primary;
                if (c.secondary)
                    look.secondary = c.secondary;
            } catch (e) {}
        }
    }

    // ---- who: the people with an account; the one who set the wallpaper last comes first ----
    property var users: []          // [{login, name}]
    property int userIndex: 0
    readonly property var user: users[userIndex] || {
        login: "",
        name: ""
    }
    property string lastUser: ""

    FileView {
        path: root.dir + "/user"
        printErrors: false
        onLoaded: {
            root.lastUser = text().trim();
            root.pickUser();
        }
    }
    Process {
        running: true
        command: ["getent", "passwd"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                for (const line of text.split("\n")) {
                    const f = line.split(":");
                    const uid = parseInt(f[2]);
                    if (f.length < 7 || uid < 1000 || uid >= 60000 || /(nologin|false)$/.test(f[6]))
                        continue;
                    found.push({
                        login: f[0],
                        name: (f[4] || "").split(",")[0].trim() || f[0]
                    });
                }
                const demo = root.preview ? Quickshell.env("DRIFTLESS_GREETER_USER") : "";
                root.users = demo ? [{
                        login: demo,
                        name: demo
                    }] : found;
                root.pickUser();
            }
        }
    }
    function pickUser() {
        const i = users.findIndex(u => u.login === lastUser);
        userIndex = Math.max(0, i);
    }
    function nextUser() {
        if (users.length < 2 || Greetd.state !== GreetdState.Inactive)
            return;
        userIndex = (userIndex + 1) % users.length;
        reset();
    }

    // ---- what starts: the Wayland sessions, the uwsm-managed Hyprland first ----
    property var sessions: []       // [{file, name, exec, desktops}]
    property int sessionIndex: 0
    readonly property var session: sessions[sessionIndex] || null

    Process {
        running: true
        command: ["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop; do [ -f \"$f\" ] || continue; " + "grep -qiE '^(NoDisplay|Hidden)=true' \"$f\" && continue; " + "printf '%s\\t%s\\t%s\\t%s\\n' \"${f##*/}\" \"$(sed -n 's/^Name=//p' \"$f\" | head -1)\" " + "\"$(sed -n 's/^Exec=//p' \"$f\" | head -1)\" \"$(sed -n 's/^DesktopNames=//p' \"$f\" | head -1)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 4 || !f[2])
                        continue;
                    found.push({
                        file: f[0].replace(/\.desktop$/, ""),
                        name: f[1] || f[0],
                        exec: f[2],
                        desktops: f[3]
                    });
                }
                found.sort((a, b) => (b.file === "hyprland-uwsm") - (a.file === "hyprland-uwsm"));
                root.sessions = found;
                root.sessionIndex = 0;
            }
        }
    }
    function nextSession() {
        if (sessions.length > 1)
            sessionIndex = (sessionIndex + 1) % sessions.length;
    }

    // ---- the login itself: greetd asks (PAM), we answer with the password ----
    property string password: ""
    property string message: ""     // what greetd says, or why it failed
    property bool failed: false
    property int fails: 0
    property bool checking: false
    property bool answered: false   // the password went to the first secret prompt of this try
    property bool asking: false     // greetd asked something else: the next submit answers it
    property bool reveal: false     // ... and it is not secret
    property bool leaving: false    // the fade out before the session starts

    function reset() {
        password = "";
        message = "";
        failed = false;
        checking = false;
        answered = false;
        asking = false;
        reveal = false;
    }

    function submit() {
        if (checking || leaving || !session || !user.login)
            return;
        if (preview) {
            message = "Preview: greetd is not running";
            return;
        }
        if (asking) {
            asking = false;
            checking = true;
            Greetd.respond(password);
            password = "";
            return;
        }
        if (password === "")
            return;
        failed = false;
        message = "";
        checking = true;
        answered = false;
        Greetd.createSession(user.login);
    }

    function launchCommand() {
        // Exec= of the session file, without the field codes (%f ...) desktop entries may have
        return session.exec.split(/\s+/).filter(a => a !== "" && !/^%/.test(a));
    }

    Connections {
        target: Greetd
        function onAuthMessage(msg, error, responseRequired, echoResponse) {
            if (!responseRequired) {
                if (msg)
                    root.message = msg;
                return;
            }
            if (!echoResponse && !root.answered) {
                root.answered = true;
                Greetd.respond(root.password);
                return;
            }
            // something else to answer (a code, a new password): ask with greetd's words
            root.checking = false;
            root.asking = true;
            root.reveal = echoResponse;
            root.password = "";
            root.message = msg;
        }
        function onAuthFailure(msg) {
            root.reset();
            root.failed = true;
            root.fails++;
            root.message = "Wrong password";
        }
        function onError(error) {
            root.reset();
            root.failed = true;
            root.message = "Could not log in (" + error + ")";
            Greetd.cancelSession();
        }
        function onReadyToLaunch() {
            root.leaving = true;
            launchTimer.start();
        }
    }
    Timer {
        id: launchTimer
        interval: 300
        onTriggered: {
            const env = ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + root.session.file];
            if (root.session.desktops)
                env.push("XDG_CURRENT_DESKTOP=" + root.session.desktops.replace(/;+$/, "").replace(/;/g, ":"));
            Greetd.launch(root.launchCommand(), env, true);
        }
    }

    // Caps Lock, read from the keyboards' LEDs (services/Keyboard.qml)
    property bool caps: false
    Process {
        id: capsProc
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2> /dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.caps = text.split("\n").some(l => l.trim() !== "" && l.trim() !== "0")
        }
    }
    Timer {
        running: true
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!capsProc.running) capsProc.running = true
    }

    property string hostname: ""
    FileView {
        path: "/etc/hostname"
        printErrors: false
        onLoaded: root.hostname = text().trim()
    }

    Process {
        id: power
    }

    // ---- the screen (cage shows it fullscreen on one output) ----
    FloatingWindow {
        id: win
        color: "black"
        implicitWidth: 1600
        implicitHeight: 900
        title: "driftless greeter"

        Image {
            id: login
            anchors.fill: parent
            source: "file://" + root.dir + "/login.png"
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            cache: false
        }

        Item {
            id: content
            anchors.fill: parent
            opacity: root.leaving ? 0 : 1
            scale: root.leaving ? 1.03 : 1
            Behavior on opacity {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            // ---- the clock, as on the lock screen ----
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height * 0.5) - 290
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: look.font
                    font.pixelSize: 96
                    font.weight: Font.ExtraLight
                    color: look.text
                    text: Qt.formatTime(time.date, "hh:mm")
                    renderType: Text.NativeRendering
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(0, 0, 0, 0.45)
                        shadowBlur: 0.8
                        shadowVerticalOffset: 4
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: look.font
                    font.pixelSize: 17
                    font.weight: Font.Medium
                    color: look.dim
                    text: Qt.locale().toString(time.date, "dddd, d. MMMM")
                    renderType: Text.NativeRendering
                }
            }
            SystemClock {
                id: time
                precision: SystemClock.Minutes
            }

            // ---- the card: the picture, the name, the password ----
            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height * 0.5) - 40
                width: 480
                height: 168
                radius: 20
                color: Qt.rgba(20 / 255, 22 / 255, 28 / 255, 0.78)
                border.width: 1
                border.color: root.failed ? Qt.alpha(look.crit, 0.45) : Qt.alpha(look.primary, 0.25)
                Behavior on border.color {
                    ColorAnimation { duration: 200 }
                }

                property real shake: 0
                transform: Translate {
                    x: card.shake
                }
                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: card; property: "shake"; to: -12; duration: 50 }
                    NumberAnimation { target: card; property: "shake"; to: 10; duration: 70 }
                    NumberAnimation { target: card; property: "shake"; to: -6; duration: 70 }
                    NumberAnimation { target: card; property: "shake"; to: 3; duration: 70 }
                    NumberAnimation { target: card; property: "shake"; to: 0; duration: 60 }
                }
                Connections {
                    target: root
                    function onFailsChanged() {
                        if (root.fails > 0)
                            shakeAnim.restart();
                    }
                }

                // the picture of the one who set the wallpaper last; a letter for anyone else
                Image {
                    id: avatar
                    x: 32
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96
                    height: 96
                    sourceSize: Qt.size(192, 192)
                    visible: status === Image.Ready && (root.user.login === root.lastUser || root.lastUser === "")
                    source: "file://" + root.dir + "/avatar.png"
                    cache: false
                    smooth: true
                    mipmap: true
                }
                Rectangle {
                    anchors.fill: avatar
                    visible: !avatar.visible
                    radius: width / 2
                    color: Qt.alpha(look.primary, 0.18)
                    Text {
                        anchors.centerIn: parent
                        font.family: look.font
                        font.pixelSize: 44
                        font.weight: Font.Bold
                        color: look.primary
                        text: (root.user.login[0] || "?").toUpperCase()
                    }
                }

                Column {
                    x: avatar.x + avatar.width + 28
                    anchors.verticalCenter: parent.verticalCenter
                    width: card.width - x - 32
                    spacing: 10

                    // the name; with more than one account a click goes to the next
                    Item {
                        width: nameRow.implicitWidth
                        height: nameRow.implicitHeight
                        Row {
                            id: nameRow
                            spacing: 4
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: look.font
                                font.pixelSize: 17
                                font.weight: Font.Bold
                                color: nameMouse.containsMouse ? look.text : look.dim
                                text: root.user.name
                                textFormat: Text.PlainText
                                renderType: Text.NativeRendering
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.users.length > 1
                                font.family: look.font
                                font.pixelSize: 14
                                color: look.faint
                                text: "\u{F0140}"
                            }
                        }
                        MouseArea {
                            id: nameMouse
                            anchors.fill: parent
                            enabled: root.users.length > 1
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.nextUser()
                        }
                    }

                    PasswordField {
                        id: field
                        theme: look
                        caps: root.caps
                        width: parent.width
                        text: root.password
                        checking: root.checking
                        failed: root.failed
                        reveal: root.reveal
                        placeholder: root.asking ? "Answer" : "Password"
                        onEdited: t => {
                            root.password = t;
                            if (t !== "")
                                root.failed = false;
                        }
                        onAccepted: root.submit()
                        onEscaped: {
                            root.password = "";
                            if (Greetd.state !== GreetdState.Inactive)
                                Greetd.cancelSession();
                            root.reset();
                        }
                    }

                    Text {
                        height: 16
                        width: parent.width
                        elide: Text.ElideRight
                        font.family: look.font
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        text: root.message !== "" ? root.message : root.caps ? "Caps Lock is on" : ""
                        color: root.failed ? look.crit : root.message === "" && root.caps ? look.warn : look.dim
                        textFormat: Text.PlainText
                        renderType: Text.NativeRendering
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: field.focusInput()
                }
            }

            // ---- at the bottom, quietly: the machine, the session, power ----
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 28
                spacing: 8

                Chip {
                    theme: look
                    icon: "\u{F0379}"
                    label: root.hostname
                    clickable: false
                    visible: root.hostname !== ""
                }
                // the session; a click picks the next one (there is rarely more than one)
                Chip {
                    theme: look
                    icon: "\u{F056E}"
                    label: root.session ? root.session.name : "no session"
                    clickable: root.sessions.length > 1
                    onClicked: root.nextSession()
                }
                Chip {
                    theme: look
                    icon: "\u{F0709}"
                    label: ""
                    onClicked: {
                        power.command = ["systemctl", "reboot"];
                        power.running = true;
                    }
                }
                Chip {
                    theme: look
                    icon: "\u{F0425}"
                    label: ""
                    onClicked: {
                        power.command = ["systemctl", "poweroff"];
                        power.running = true;
                    }
                }
            }
        }

        Component.onCompleted: field.focusInput()
    }
}
