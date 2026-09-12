pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

StyledClippingRect {
    id: root

    required property ShellScreen screen
    required property bool fullscreen

    readonly property bool onSpecial: Hypr.monitorFor(screen)?.lastIpcObject.specialWorkspace?.name !== ""
    readonly property int activeWsId: Hypr.monitorFor(screen).activeWorkspace?.id ?? 1

    readonly property var occupied: {
        // Other monitors' workspaces count as unoccupied when hiding unoccupied
        const mon = !Config.bar.workspaces.showUnoccupied ? Hypr.monitorFor(screen) : null;
        const occ = {};
        for (const ws of Hypr.workspaces.values)
            occ[ws.id] = ws.lastIpcObject.windows > 0 && (!mon || ws.monitor === mon);
        return occ;
    }
    readonly property int groupOffset: Math.floor((activeWsId - 1) / Config.bar.workspaces.shown) * Config.bar.workspaces.shown
    readonly property real workspaceSpacing: Math.floor(Tokens.spacing.extraSmall)
    readonly property bool revealTransitionRunning: {
        for (let i = 0; i < workspaces.count; ++i) {
            const workspace = workspaces.itemAt(i) as Workspace;
            if (workspace?.revealTransitionRunning)
                return true;
        }

        return false;
    }

    // Horizontal (top/bottom bar) support
    readonly property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"

    property real blur: onSpecial ? 1 : 0

    function workspaceIndex(id: int): int {
        let index = id - 1;
        while (index < 0)
            index += Config.bar.workspaces.shown;
        return index % Config.bar.workspaces.shown;
    }

    implicitWidth: isHorizontal ? (layout.implicitWidth + Tokens.padding.small) : Tokens.sizes.bar.innerWidth
    implicitHeight: isHorizontal ? Tokens.sizes.bar.innerWidth : (layout.implicitHeight + Tokens.padding.small)

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    Item {
        anchors.fill: parent
        scale: root.onSpecial ? 0.8 : 1
        opacity: root.onSpecial ? 0.5 : 1
        visible: !root.fullscreen

        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: root.blur
            blurMax: 32
        }

        Loader {
            asynchronous: true
            active: Config.bar.workspaces.occupiedBg

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            sourceComponent: OccupiedBg {
                workspaces: workspaces
                occupied: root.occupied
                groupOffset: root.groupOffset
                layoutTransitionRunning: root.revealTransitionRunning
                workspaceIndex: root.workspaceIndex
            }
        }

        GridLayout {
            id: layout

            anchors.centerIn: parent
            columns: root.isHorizontal ? -1 : 1
            rows: root.isHorizontal ? 1 : -1
            flow: root.isHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            columnSpacing: 0
            rowSpacing: 0

            Repeater {
                id: workspaces

                model: Config.bar.workspaces.shown

                Workspace {
                    activeWsId: root.activeWsId
                    occupied: root.occupied
                    groupOffset: root.groupOffset
                    shouldShow: Config.bar.workspaces.showUnoccupied || isOccupied || ws === root.activeWsId
                    isHorizontal: root.isHorizontal

                    workspaceRepeater: workspaces
                    layoutSpacing: root.workspaceSpacing
                }
            }
        }

        Loader {
            asynchronous: true
            anchors.horizontalCenter: root.isHorizontal ? undefined : parent.horizontalCenter
            anchors.verticalCenter: root.isHorizontal ? parent.verticalCenter : undefined
            active: Config.bar.workspaces.activeIndicator

            sourceComponent: ActiveIndicator {
                activeWsId: root.activeWsId
                workspaces: workspaces
                mask: layout
                fullscreen: root.fullscreen
                layoutTransitionRunning: root.revealTransitionRunning
                workspaceIndex: root.workspaceIndex
            }
        }

        MouseArea {
            anchors.fill: layout
            onClicked: event => {
                const ws = (layout.childAt(event.x, event.y) as Workspace)?.ws;
                if (!ws)
                    return;
                if (Hypr.activeWsId !== ws)
                    Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "${ws}" })` : `workspace ${ws}`);
                else
                    Hypr.dispatch(Hypr.usingLua ? 'hl.dsp.workspace.toggle_special("special")' : "togglespecialworkspace special");
            }
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: specialWs

        asynchronous: true

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall

        active: opacity > 0

        scale: root.onSpecial ? 1 : 0.5
        opacity: root.onSpecial ? 1 : 0

        sourceComponent: SpecialWorkspaces {
            screen: root.screen
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Behavior on blur {
        Anim {
            type: Anim.StandardSmall
        }
    }
}
