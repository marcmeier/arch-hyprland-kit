import QtQuick
import qs.services

// The weather now (wttr.in, scripts/weather.py). Click: the next hours and three days.
Seg {
    id: seg

    readonly property var w: Feeds.weather.data
    shown: !!(w && w.icon)
    spacing: 6
    tip: w && w.desc ? w.desc + "<font color='" + Theme.dim + "'>  ·  feels " + w.feels + "°</font>" : ""

    onClicked: togglePopup()

    popupKey: "weather"
    popupComponent: Component {
        WeatherPopup {}
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: seg.w?.icon ?? ""
        size: seg.compact ? 16 : 17
        color: Theme.accent2
    }
    Label {
        anchors.verticalCenter: parent.verticalCenter
        text: seg.w ? seg.w.temp + "°C" : ""
        font.pixelSize: seg.compact ? 13 : 14
    }
}
