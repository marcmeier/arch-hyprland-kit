pragma Singleton

import Quickshell
import QtQuick

// Leaving the desk: lock, log out, suspend, reboot, shut down, in one place for the power menu
// (power/PowerMenu.qml), the lock screen (lock/Lock.qml) and the IPC. Suspend locks first, so the
// machine never wakes up open, also without hypridle.
Singleton {
    id: session

    // set by the lock screen
    property bool locked: false
    signal lockRequested
    signal powerMenuRequested

    // open or close the power menu
    function powerMenu() {
        powerMenuRequested();
    }

    function lock() {
        lockRequested();
    }

    function logout() {
        Actions.run(["uwsm", "stop"]);
    }

    // the lock screen is up (the compositor confirmed it) before the machine sleeps
    function suspend() {
        suspendPending = true;
        if (locked)
            lockSecured();
        else {
            lock();
            suspendLater.restart();
        }
    }
    property bool suspendPending: false
    function lockSecured() {
        if (!suspendPending)
            return;
        suspendPending = false;
        suspendLater.stop();
        Actions.run(["systemctl", "suspend"]);
    }

    function reboot() {
        Actions.run(["systemctl", "reboot"]);
    }

    function poweroff() {
        Actions.run(["systemctl", "poweroff"]);
    }

    // no lock screen after 2 s (the shell's lock failed): sleep anyway, hypridle locks before sleep
    Timer {
        id: suspendLater
        interval: 2000
        onTriggered: {
            session.suspendPending = false;
            Actions.run(["systemctl", "suspend"]);
        }
    }
}
