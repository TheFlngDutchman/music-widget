import QtQuick
import QtQuick.Layouts
import "../../services"
import "../components"

// Live settings: every control writes straight to Config (debounced save),
// and the window/theme bindings apply the change immediately.
Item {
    id: page

    // switch-based accessors so bindings track the actual color properties
    // (dynamic key lookup on the JsonObject wouldn't re-evaluate reliably)
    function overrideFor(key) {
        switch (key) {
        case "accent": return Config.colors.accent;
        case "background": return Config.colors.background;
        case "foreground": return Config.colors.foreground;
        case "teal": return Config.colors.teal;
        }
        return "";
    }

    function setOverride(key, value) {
        switch (key) {
        case "accent": Config.colors.accent = value; break;
        case "background": Config.colors.background = value; break;
        case "foreground": Config.colors.foreground = value; break;
        case "teal": Config.colors.teal = value; break;
        }
    }

    function effectiveColor(key) {
        switch (key) {
        case "accent": return Theme.accent;
        case "background": return Theme.bg;
        case "foreground": return Theme.fg;
        case "teal": return Theme.teal;
        }
        return Theme.fg;
    }

    component SectionLabel: StyledText {
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 2
        opacity: 0.35
        Layout.topMargin: 6
    }

    component RowLabel: StyledText {
        font.pixelSize: Theme.fontSize - 1
        opacity: 0.7
        Layout.preferredWidth: 80
    }

    component ActionButton: Rectangle {
        id: btn

        property string label: ""
        property bool primary: false

        signal clicked()

        implicitWidth: btnLbl.implicitWidth + 20
        implicitHeight: btnLbl.implicitHeight + 8
        radius: 4
        color: primary
            ? (btnMouse.containsMouse ? Theme.accent : Theme.accentBg)
            : (btnMouse.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent")
        border.color: primary ? "transparent" : Theme.border

        Text {
            id: btnLbl
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? Theme.accentFg : Theme.fg
            opacity: btn.primary ? 1.0 : 0.7
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: btn.primary
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component SettingInput: Rectangle {
        id: field

        property string value: ""
        property string placeholder: ""

        signal committed(string v)

        implicitHeight: input.implicitHeight + 10
        radius: 4
        color: Theme.alpha(Theme.fg, input.activeFocus ? 0.10 : 0.07)
        border.color: Theme.border

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: TextInput.AlignVCenter
            text: field.value
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            clip: true
            selectByMouse: true
            onEditingFinished: {
                if (text !== field.value)
                    field.committed(text);
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: field.placeholder
                color: Theme.fg
                opacity: 0.3
                font: input.font
                visible: input.text.length === 0 && !input.activeFocus
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 10
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 7

            SectionLabel { text: "WINDOW" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLabel { text: "Position" }

                Flow {
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: ["top-left", "top", "top-right", "bottom-left", "bottom", "bottom-right", "floating"]

                        Chip {
                            required property string modelData
                            label: modelData
                            current: Config.window.anchor === modelData
                            onClicked: Config.window.anchor = modelData
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: Config.window.anchor === "floating"
                spacing: 4

                RowLabel { text: "" }

                StyledText {
                    Layout.fillWidth: true
                    text: "drag the widget by its header to move it"
                    font.pixelSize: Theme.fontSize - 2
                    opacity: 0.35
                }
            }

            RowLayout {
                spacing: 4

                RowLabel { text: "Size" }

                Stepper {
                    value: Config.window.width
                    from: 360
                    to: 1600
                    step: 20
                    onStepped: v => Config.window.width = v
                }

                StyledText { text: "×"; opacity: 0.4; font.pixelSize: Theme.fontSize - 1 }

                Stepper {
                    value: Config.window.height
                    from: 240
                    to: 1000
                    step: 20
                    onStepped: v => Config.window.height = v
                }
            }

            RowLayout {
                spacing: 6

                RowLabel { text: "Margins" }

                StyledText { text: "T"; opacity: 0.35; font.pixelSize: Theme.fontSize - 2 }
                Stepper {
                    value: Config.window.marginTop
                    to: 64
                    step: 2
                    onStepped: v => Config.window.marginTop = v
                }

                StyledText { text: "R"; opacity: 0.35; font.pixelSize: Theme.fontSize - 2 }
                Stepper {
                    value: Config.window.marginRight
                    to: 64
                    step: 2
                    onStepped: v => Config.window.marginRight = v
                }

                StyledText { text: "B"; opacity: 0.35; font.pixelSize: Theme.fontSize - 2 }
                Stepper {
                    value: Config.window.marginBottom
                    to: 64
                    step: 2
                    onStepped: v => Config.window.marginBottom = v
                }

                StyledText { text: "L"; opacity: 0.35; font.pixelSize: Theme.fontSize - 2 }
                Stepper {
                    value: Config.window.marginLeft
                    to: 64
                    step: 2
                    onStepped: v => Config.window.marginLeft = v
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLabel { text: "Monitor" }

                SettingInput {
                    Layout.preferredWidth: 160
                    value: Config.window.monitor
                    placeholder: "auto"
                    onCommitted: v => Config.window.monitor = v.trim()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "output name, e.g. DP-1"
                    font.pixelSize: Theme.fontSize - 2
                    opacity: 0.3
                }
            }

            SectionLabel { text: "LOOK" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLabel { text: "Font" }

                SettingInput {
                    Layout.preferredWidth: 220
                    value: Config.font.family
                    placeholder: "font family"
                    onCommitted: v => {
                        if (v.trim() !== "")
                            Config.font.family = v.trim();
                    }
                }

                Stepper {
                    value: Config.font.size
                    from: 8
                    to: 20
                    onStepped: v => Config.font.size = v
                }
            }

            RowLayout {
                spacing: 4

                RowLabel { text: "Album art" }

                Stepper {
                    value: Config.controls.artSize
                    from: 48
                    to: 160
                    step: 8
                    onStepped: v => Config.controls.artSize = v
                }
            }

            Repeater {
                model: [
                    { key: "accent", label: "Accent" },
                    { key: "background", label: "Background" },
                    { key: "foreground", label: "Foreground" },
                    { key: "teal", label: "Teal" }
                ]

                RowLayout {
                    id: colorRow

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 6

                    RowLabel { text: colorRow.modelData.label }

                    Rectangle {
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        radius: 3
                        color: page.effectiveColor(colorRow.modelData.key)
                        border.color: Theme.border
                    }

                    SettingInput {
                        Layout.preferredWidth: 110
                        value: page.overrideFor(colorRow.modelData.key)
                        placeholder: "omarchy"
                        onCommitted: v => {
                            const hex = v.trim();
                            if (hex === "" || /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(hex))
                                page.setOverride(colorRow.modelData.key, hex);
                        }
                    }

                    IconButton {
                        text: "󰦛"
                        textSize: 12
                        dimmed: 0.5
                        visible: page.overrideFor(colorRow.modelData.key) !== ""
                        onClicked: page.setOverride(colorRow.modelData.key, "")
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: colorRow.modelData.key === "accent" && page.overrideFor("accent") === ""
                            ? "empty = follow omarchy theme" : ""
                        font.pixelSize: Theme.fontSize - 2
                        opacity: 0.3
                    }
                }
            }

            SectionLabel { text: "SPOTIFY" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLabel { text: "Account" }

                StyledText {
                    text: SpotifyAuth.authState === "authenticated" ? "Connected"
                        : SpotifyAuth.authState === "authorizing" ? "Waiting for browser…"
                        : SpotifyAuth.authState === "no-client-id" ? "Not set up — see the Playlists tab"
                        : "Not connected"
                    font.pixelSize: Theme.fontSize - 1
                    color: SpotifyAuth.authState === "authenticated" ? Theme.accent : Theme.fg
                    opacity: SpotifyAuth.authState === "authenticated" ? 1.0 : 0.55
                }

                Item { Layout.fillWidth: true }

                ActionButton {
                    label: "Connect"
                    primary: true
                    visible: SpotifyAuth.authState === "unauthenticated"
                    onClicked: SpotifyAuth.begin()
                }

                ActionButton {
                    label: "Sign out"
                    visible: SpotifyAuth.authState === "authenticated"
                    onClicked: SpotifyAuth.signOut()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLabel { text: "spotifyd" }

                StyledText {
                    text: (Spotifyd.serviceActive ? "running" : "stopped")
                        + " · " + (Spotifyd.hasCredentials ? "authenticated" : "no credentials")
                    font.pixelSize: Theme.fontSize - 1
                    opacity: 0.55
                }

                Item { Layout.fillWidth: true }

                ActionButton {
                    label: "Start"
                    visible: !Spotifyd.serviceActive
                    onClicked: Spotifyd.startService()
                }

                ActionButton {
                    label: Spotifyd.authenticating ? "Waiting…" : "Authenticate"
                    visible: !Spotifyd.hasCredentials && !Spotifyd.authenticating
                    onClicked: Spotifyd.authenticate()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLabel { text: "Redirect" }

                StyledText {
                    Layout.fillWidth: true
                    text: SpotifyAuth.redirectUri
                    font.pixelSize: Theme.fontSize - 2
                    opacity: 0.35
                    elide: Text.ElideRight
                }
            }

            SectionLabel { text: "VISUALIZER" }

            StyledText {
                Layout.fillWidth: true
                text: "Style, bars, sensitivity and smoothing live in the 󰢻 menu on the Visualizer tab."
                font.pixelSize: Theme.fontSize - 2
                opacity: 0.35
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
        }
    }
}
