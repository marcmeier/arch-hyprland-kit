pragma Singleton

import Quickshell
import QtQuick

// Nerd Font glyphs that change with a level (Wi-Fi, volume, battery).
Singleton {
    function wifi(strength) {
        return strength > 0.75 ? "\u{F0928}" : strength > 0.5 ? "\u{F0925}" : strength > 0.25 ? "\u{F0922}" : "\u{F091F}";
    }

    function volume(level, muted, headphones) {
        if (muted)
            return "\u{F075F}";
        if (headphones)
            return "\u{F02CB}";
        return level > 0.66 ? "\u{F057E}" : level > 0.33 ? "\u{F0580}" : "\u{F057F}";
    }

    function mic(muted) {
        return muted ? "\u{F036D}" : "\u{F036C}";
    }

    // a Bluetooth device by BlueZ's icon name (audio-headset, input-mouse, ...)
    function bluetoothDevice(icon) {
        const table = [[/headset/, "\u{F02CE}"], [/headphone/, "\u{F02CB}"], [/audio|speaker/, "\u{F04C3}"],
                       [/keyboard/, "\u{F030C}"], [/mouse|tablet/, "\u{F037D}"], [/gaming|joystick/, "\u{F0297}"],
                       [/phone/, "\u{F011C}"], [/watch/, "\u{F0589}"]];
        const hit = table.find(t => t[0].test(icon || ""));
        return hit ? hit[1] : "\u{F00AF}";
    }

    // percent 0..100
    function battery(percent, charging) {
        if (charging) {
            const steps = [[95, "\u{F0085}"], [85, "\u{F008B}"], [70, "\u{F008A}"], [50, "\u{F0089}"],
                           [35, "\u{F0088}"], [25, "\u{F0087}"], [0, "\u{F0086}"]];
            return steps.find(s => percent >= s[0])[1];
        }
        if (percent >= 95)
            return "\u{F0079}";
        if (percent < 8)
            return "\u{F0083}";
        const idx = Math.min(8, Math.max(0, Math.round(percent / 10) - 1));
        return String.fromCodePoint(0xF007A + idx);
    }
}
