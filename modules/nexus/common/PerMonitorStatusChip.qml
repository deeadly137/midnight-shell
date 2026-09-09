pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.services

IconButton {
    id: root

    property var configNode
    property string propertyName: ""

    readonly property bool isOverridden: {
        if (!configNode || !propertyName)
            return false;
        const targetObj = configNode[propertyName];
        const _dummy1 = (targetObj && targetObj.values !== undefined) ? targetObj.values : targetObj;
        return configNode.isOverride(propertyName);
    }

    visible: isOverridden
    icon: "restart_alt"
    type: IconButton.Text
    font: Tokens.font.icon.small
    inactiveOnColour: Colours.palette.m3tertiary

    Layout.alignment: Qt.AlignVCenter

    onClicked: {
        if (root.configNode && root.propertyName !== "") {
            root.configNode.resetOption(root.propertyName);
            GlobalConfig.forScreen(Config.screen).save();
        }
    }
}
