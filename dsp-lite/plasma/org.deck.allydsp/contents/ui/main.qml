pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    preferredRepresentation: compactRepresentation

    property bool dspActive: false
    property string preset: "game/balanced"
    property string micState: "on"

    readonly property var profileIds: ["game", "dynamic", "movie", "music", "voice"]
    readonly property var voicingIds: ["balanced", "detailed", "warm"]

    function t(p, e) { return Qt.locale().name.indexOf("pl") === 0 ? p : e }
    function profileName(id) {
        var pl = { game: "Gra", dynamic: "Dynamiczny", movie: "Film", music: "Muzyka", voice: "Głos" }
        var en = { game: "Game", dynamic: "Dynamic", movie: "Movie", music: "Music", voice: "Voice" }
        return t(pl[id] || id, en[id] || id)
    }
    function voicingName(id) {
        var pl = { balanced: "Zbalansowany", detailed: "Szczegółowy", warm: "Ciepły" }
        var en = { balanced: "Balanced", detailed: "Detailed", warm: "Warm" }
        return t(pl[id] || id, en[id] || id)
    }
    function curProfile() { return (preset.split("/")[0] || "game") }
    function curVoicing() { return (preset.split("/")[1] || "balanced") }

    toolTipMainText: "Ally DSP"
    toolTipSubText: (dspActive ? t("Włączony", "On") : t("Wyłączony", "Off"))
        + " · " + profileName(curProfile()) + " / " + voicingName(curVoicing())

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            var out = (data["stdout"] || "").trim()
            try {
                var j = JSON.parse(out)
                root.dspActive = (j.active === 1)
                if (j.preset) root.preset = j.preset
                if (j.mic) root.micState = j.mic
            } catch (e) { }
            exec.disconnectSource(sourceName)
        }
        function run(cmd) { connectSource(cmd) }
    }

    function refresh() { exec.run("/home/deck/.local/bin/dsp json") }
    function setOn(on) {
        exec.run("/home/deck/ally-dsp-fix/dsp.sh " + (on ? "on" : "off"))
        later.restart()
    }
    function toggleMic() {
        exec.run("/home/deck/ally-dsp-fix/dsp.sh mic " + (root.micState === "on" ? "off" : "on"))
        later.restart()
    }
    function setPreset(profile, voicing) {
        root.preset = profile + "/" + voicing
        exec.run("/home/deck/ally-dsp-fix/dsp.sh preset " + profile + " " + voicing)
        later.restart()
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: later
        interval: 3500
        repeat: false
        onTriggered: root.refresh()
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.dspActive ? root.t("Wyłącz ulepszenie audio", "Turn audio enhancement off") : root.t("Włącz ulepszenie audio", "Turn audio enhancement on")
            icon.name: "media-playback-start"
            onTriggered: root.setOn(!root.dspActive)
        },
        PlasmaCore.Action {
            text: root.micState === "on"
                ? root.t("Wyłącz ulepszenie mikrofonu", "Turn microphone enhancement off")
                : root.t("Włącz ulepszenie mikrofonu", "Turn microphone enhancement on")
            icon.name: root.micState === "on" ? "audio-input-microphone" : "audio-input-microphone-muted"
            onTriggered: root.toggleMic()
        },
        PlasmaCore.Action {
            text: root.t("Profil", "Profile")
            enabled: false
        },
        PlasmaCore.Action {
            text: root.profileName("game")
            checkable: true
            checked: root.curProfile() === "game"
            onTriggered: root.setPreset("game", root.curVoicing())
        },
        PlasmaCore.Action {
            text: root.profileName("dynamic")
            checkable: true
            checked: root.curProfile() === "dynamic"
            onTriggered: root.setPreset("dynamic", root.curVoicing())
        },
        PlasmaCore.Action {
            text: root.profileName("movie")
            checkable: true
            checked: root.curProfile() === "movie"
            onTriggered: root.setPreset("movie", root.curVoicing())
        },
        PlasmaCore.Action {
            text: root.profileName("music")
            checkable: true
            checked: root.curProfile() === "music"
            onTriggered: root.setPreset("music", root.curVoicing())
        },
        PlasmaCore.Action {
            text: root.profileName("voice")
            checkable: true
            checked: root.curProfile() === "voice"
            onTriggered: root.setPreset("voice", root.curVoicing())
        },
        PlasmaCore.Action {
            text: root.t("Voicing", "Voicing")
            enabled: false
        },
        PlasmaCore.Action {
            text: root.voicingName("balanced")
            checkable: true
            checked: root.curVoicing() === "balanced"
            onTriggered: root.setPreset(root.curProfile(), "balanced")
        },
        PlasmaCore.Action {
            text: root.voicingName("detailed")
            checkable: true
            checked: root.curVoicing() === "detailed"
            onTriggered: root.setPreset(root.curProfile(), "detailed")
        },
        PlasmaCore.Action {
            text: root.voicingName("warm")
            checkable: true
            checked: root.curVoicing() === "warm"
            onTriggered: root.setPreset(root.curProfile(), "warm")
        }
    ]

    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            // ikona symboliczna = kolor z motywu (jasna na ciemnym panelu i odwrotnie),
            // glosniki odrozniaja ja od ikony glosnosci
            source: "audio-speakers-symbolic"
            opacity: root.dspActive ? 1.0 : 0.45
            active: compact.containsMouse
        }
        Text {
            // znacznik "ulepszenie", rysowany kolorem motywu
            text: "+"
            visible: root.dspActive
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 0
            anchors.bottomMargin: -Math.round(parent.height * 0.12)
            font.bold: true
            font.pixelSize: Math.max(8, Math.round(parent.height * 0.5))
            color: Kirigami.Theme.textColor
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            text: "Ally DSP — " + root.t("ulepszenie audio", "audio enhancement") + ": " + (root.dspActive ? root.t("włączone", "on") : root.t("wyłączone", "off"))
            font.bold: true
        }
        QQC2.Label {
            text: root.profileName(root.curProfile()) + " / " + root.voicingName(root.curVoicing())
            opacity: 0.7
        }
        QQC2.Button {
            Layout.fillWidth: true
            text: root.dspActive ? root.t("Wyłącz ulepszenie audio", "Turn audio enhancement off") : root.t("Włącz ulepszenie audio", "Turn audio enhancement on")
            onClicked: root.setOn(!root.dspActive)
        }
        QQC2.Label {
            text: root.t("Mikrofon", "Microphone") + ": "
                + (root.micState === "on" ? root.t("ulepszenie włączone", "enhancement on") : root.t("bez ulepszeń", "no enhancement"))
            font.bold: true
        }
        QQC2.Button {
            Layout.fillWidth: true
            text: root.micState === "on"
                ? root.t("Wyłącz ulepszenie mikrofonu", "Turn microphone enhancement off")
                : root.t("Włącz ulepszenie mikrofonu", "Turn microphone enhancement on")
            onClicked: root.toggleMic()
        }
        QQC2.Label {
            text: root.t("Profil", "Profile")
            font.bold: true
        }
        GridLayout {
            columns: 2
            Layout.fillWidth: true
            Repeater {
                model: root.profileIds
                QQC2.Button {
                    required property string modelData
                    Layout.fillWidth: true
                    text: root.profileName(modelData)
                    checkable: true
                    checked: root.curProfile() === modelData
                    onClicked: root.setPreset(modelData, root.curVoicing())
                }
            }
        }
        QQC2.Label {
            text: root.t("Voicing", "Voicing")
            font.bold: true
        }
        GridLayout {
            columns: 3
            Layout.fillWidth: true
            Repeater {
                model: root.voicingIds
                QQC2.Button {
                    required property string modelData
                    Layout.fillWidth: true
                    text: root.voicingName(modelData)
                    checkable: true
                    checked: root.curVoicing() === modelData
                    onClicked: root.setPreset(root.curProfile(), modelData)
                }
            }
        }
        QQC2.Button {
            Layout.fillWidth: true
            text: root.t("Odśwież", "Refresh")
            onClicked: root.refresh()
        }
    }
}
