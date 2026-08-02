pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Components
import Caelestia.Services
import Caelestia.Config
import qs.services

Item {
    id: root

    required property XEmbedClient modelData

    implicitWidth: Tokens.font.body.small.pointSize * 2
    implicitHeight: Tokens.font.body.small.pointSize * 2

    XEmbedItem {
        id: xembed

        anchors.fill: parent
        windowId: root.modelData.windowId
    }
}
