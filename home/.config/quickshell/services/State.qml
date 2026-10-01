pragma Singleton

import Quickshell
import QtQuick

// Choices you make in the bar that outlive a reload of the shell.
Singleton {
    property alias idleInhibited: keep.idleInhibited

    PersistentProperties {
        id: keep
        reloadableId: "driftless-state"
        property bool idleInhibited: false
    }
}
