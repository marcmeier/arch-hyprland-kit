pragma Singleton

import Quickshell
import Quickshell.Services.UPower
import QtQuick

// Words for the battery pill and its popup.
Singleton {
    function hm(seconds) {
        const h = Math.floor(seconds / 3600), m = Math.round(seconds % 3600 / 60);
        return h ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`;
    }

    function state(dev) {
        if (!dev)
            return "";
        switch (dev.state) {
        case UPowerDeviceState.Charging:
            return dev.timeToFull > 0 ? `full in ${hm(dev.timeToFull)}` : "charging";
        case UPowerDeviceState.Discharging:
            return dev.timeToEmpty > 0 ? `${hm(dev.timeToEmpty)} left` : "on battery";
        case UPowerDeviceState.FullyCharged:
            return "fully charged";
        case UPowerDeviceState.PendingCharge:
            return "plugged in, not charging";
        default:
            return "";
        }
    }

    function summary(dev) {
        if (!dev)
            return "";
        const rate = Math.abs(dev.changeRate);
        return `Battery ${Math.round(dev.percentage * 100)}%<font color='${Theme.dim}'>  ·  ${state(dev)}`
               + (rate > 0.05 ? `  ·  ${rate.toFixed(1)} W` : "") + "</font>";
    }
}
