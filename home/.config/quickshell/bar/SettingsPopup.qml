import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// The desktop settings (a click on the avatar; walker menus before): the wallpaper with the folder's
// thumbnails, the bar's size and which widgets it shows, the monitors, and the way to the sync and the
// keys. Every choice is this machine's own (scripts/settings-menu.sh, scripts/bar_layout.py).
Item {
    id: root

    property var popup
    property var bar

    readonly property string scripts: Quickshell.shellDir + "/scripts"
    readonly property string menu: scripts + "/settings-menu.sh"
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"

    property var walls: []          // [{image, thumb}], newest first
    property var widgets: []        // bar_layout.py --widgets
    readonly property bool laptopPanel: Hyprland.monitors.values.some(m => /^eDP-/.test(m.name))

    implicitWidth: 780
    implicitHeight: column.implicitHeight

    function run(args) {
        Actions.launch([root.menu].concat(args));
    }
    // a program with a window of its own: the popup makes way
    function open(args) {
        run(args);
        if (popup)
            popup.close();
    }

    // ---- what there is ----

    Process {
        running: true
        command: [root.menu, "wallpapers"]
        stdout: StdioCollector {
            onStreamFinished: root.walls = text.split("\n").filter(l => l.includes("\t")).map(l => {
                const [image, thumb] = l.split("\t");
                return { image: image, thumb: thumb };
            })
        }
    }
    FileView {
        id: current
        path: Quickshell.env("HOME") + "/.cache/theme/wall.source"
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
    }
    FileView {
        id: customMonitors
        path: root.stateDir + "/hypr/monitors.lua"
        printErrors: false
    }

    Process {
        id: widgetList
        running: true
        command: [root.scripts + "/bar_layout.py", "--widgets"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // the user pill is the way in here: it stays
                    root.widgets = JSON.parse(text).filter(w => w.id !== "group/user" && w.group !== "group/user");
                } catch (e) {}
            }
        }
    }
    // the layout changed (here or in the widget manager): read the list again
    Connections {
        target: BarLayout
        function onSavedChanged() {
            widgetList.running = true;
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 14

        // ---- who and where; a click on the picture changes it ----
        Item {
            width: column.width
            height: who.implicitHeight
            Row {
                id: who
                spacing: 12
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    Image {
                        anchors.fill: parent
                        sourceSize: Qt.size(80, 80)
                        source: Theme.avatarVersion >= 0 ? "file://" + Theme.avatar : ""
                        cache: false
                        smooth: true
                        mipmap: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(0, 0, 0, 0.5)
                        opacity: faceMouse.containsMouse ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: 120 }
                        }
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{F03EB}"
                            size: 16
                        }
                    }
                    MouseArea {
                        id: faceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.open(["avatar"])
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Label {
                        text: Feeds.userName
                        bold: true
                        font.pixelSize: 15
                    }
                    Label {
                        small: true
                        dim: true
                        text: "Settings of this machine"
                    }
                }
            }
            PButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                icon: "\u{F06BC}"
                text: "Picture …"
                onClicked: root.open(["avatar"])
            }
        }

        Separator {
            width: column.width
        }

        Row {
            spacing: 24

            // left: the wallpaper, the monitors, the rest
            Column {
                id: left
                width: 360
                spacing: 12

                // ---- wallpaper ----
                Caption {
                    text: "Wallpaper and colours"
                }
                Flickable {
                    width: parent.width
                    height: Math.min(grid.implicitHeight, 3 * Math.round((grid.width - 2 * grid.spacing) / 3 * 9 / 16) + 2 * grid.spacing)
                    contentHeight: grid.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Grid {
                        id: grid
                        width: parent.width
                        columns: 3
                        spacing: 8
                        Repeater {
                            model: root.walls
                            Rectangle {
                                id: tile
                                required property var modelData
                                readonly property bool active: current.text().trim() === modelData.image
                                width: (grid.width - 2 * grid.spacing) / 3
                                height: Math.round(width * 9 / 16)
                                radius: 9
                                color: Theme.well
                                border.width: active ? 2 : mouse.containsMouse ? 1 : 0
                                border.color: active ? Theme.accent2 : Theme.cardBorder
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: tile.active ? 3 : 1
                                    source: "file://" + tile.modelData.thumb
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    opacity: mouse.containsMouse || tile.active ? 1 : 0.85
                                }
                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.run(["wallpaper-pick", tile.modelData.image])
                                }
                            }
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    PButton {
                        icon: "\u{F02E9}"
                        text: "Browse …"
                        onClicked: root.open(["wallpaper"])
                    }
                    PButton {
                        icon: "\u{F049D}"
                        text: "Random"
                        onClicked: root.run(["wallpaper-pick", "random"])
                    }
                    PButton {
                        icon: "\u{F054C}"
                        text: "Previous"
                        onClicked: root.run(["wallpaper-pick", "previous"])
                    }
                    PButton {
                        icon: "\u{F024F}"
                        text: "Other image …"
                        onClicked: root.open(["wallpaper-pick", "other"])
                    }
                    PButton {
                        icon: "\u{F0770}"
                        text: "Folder"
                        onClicked: root.open(["wallpaper-pick", "folder"])
                    }
                }

                Separator {}

                // ---- monitors, sync, keys ----
                Caption {
                    text: "Monitors"
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    PButton {
                        icon: "\u{F0379}"
                        text: "Arrange …"
                        onClicked: root.open(["monitors-arrange"])
                    }
                    PButton {
                        visible: root.laptopPanel
                        icon: "\u{F037A}"
                        text: "Display mode"
                        onClicked: root.open(["display-mode"])
                    }
                    PButton {
                        visible: customMonitors.loaded
                        icon: "\u{F0450}"
                        text: "Automatic layout"
                        onClicked: {
                            root.run(["monitors-reset"]);
                            customMonitors.reload();
                        }
                    }
                }

                Separator {}

                Flow {
                    width: parent.width
                    spacing: 6
                    PButton {
                        icon: "\u{F04E6}"
                        text: "Sync with your machines …"
                        onClicked: root.open(["sync"])
                    }
                    PButton {
                        icon: "\u{F030C}"
                        text: "Keybindings"
                        onClicked: root.open(["keys"])
                    }
                }
            }

            // right: the bar
            Column {
                id: right
                width: root.width - left.width - 24
                spacing: 12

                // ---- the bar ----
                Caption {
                    text: "Bar"
                }
                Row {
                    spacing: 6
                    Repeater {
                        model: [["auto", "Automatic"], ["spacious", "Full size"], ["compact", "Compact"]]
                        PButton {
                            required property var modelData
                            text: modelData[1]
                            checked: BarLayout.mode === modelData[0]
                            onClicked: Actions.run([root.scripts + "/bar_layout.py", "--mode", modelData[0]])
                        }
                    }
                }
                Label {
                    small: true
                    dim: true
                    text: "Widgets: a click shows or hides one"
                }
                // which widgets show: a click switches one on or off; the order is the widget manager's job
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.widgets
                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool shownNow: !modelData.hidden
                            width: chipText.implicitWidth + 22
                            height: 28
                            radius: 8
                            color: shownNow ? Qt.alpha(Theme.accent2, 0.14) : chipMouse.containsMouse ? Theme.hover : "transparent"
                            border.width: 1
                            border.color: shownNow ? Qt.alpha(Theme.accent2, 0.45) : Theme.cardBorder
                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }
                            Label {
                                id: chipText
                                anchors.centerIn: parent
                                text: (chip.modelData.group ? "· " : "") + chip.modelData.name
                                font.pixelSize: 12
                                color: chip.shownNow ? Theme.text : Theme.faint
                            }
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Actions.run([root.scripts + "/bar_layout.py", "--toggle", chip.modelData.id])
                            }
                        }
                    }
                }
                PButton {
                    icon: "\u{F04E1}"
                    text: "Move widgets …"
                    onClicked: root.open(["widgets"])
                }

            }
        }
    }

    component Separator: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.separator
    }
}
