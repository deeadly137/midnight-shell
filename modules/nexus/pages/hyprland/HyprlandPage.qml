import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Hyprland")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2



        NavRow {
            first: true
            icon: "data_object"
            text: qsTr("Variables")
            subtext: qsTr("Manage your hyprland variables")
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            icon: "keyboard"
            text: qsTr("Keybinds")
            subtext: qsTr("Manage your hyprland keybinds")
            onClicked: root.nState.openSubPage(2)
        }

        NavRow {
            icon: "settings_suggest"
            text: qsTr("User configuration")
            subtext: qsTr("Advanced configuration options")
            onClicked: root.nState.openSubPage(3)
        }

        SectionHeader {
            text: qsTr("Behavior")
        }

        ToggleRow {
            last: true
            text: qsTr("Restart on display change")
            subtext: qsTr("Restart the shell when a new display is connected (fixes surfaces not appearing on the new screen)")
            checked: GlobalConfig.general.restartOnDisplayChange
            onToggled: {
                GlobalConfig.general.restartOnDisplayChange = checked;
                GlobalConfig.save();
            }
        }
    }
}
