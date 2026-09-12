pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import M3Shapes
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

GridLayout {
    id: root

    required property int index
    required property int activeWsId
    required property var occupied
    required property int groupOffset
    required property bool shouldShow
    required property bool isHorizontal
    required property Repeater workspaceRepeater
    required property real layoutSpacing

    readonly property bool isWorkspace: true // Flag for finding workspace children

    // Unanimated prop for others to use as reference
    readonly property int size: isHorizontal ? (implicitWidth + (hasWindows ? Tokens.padding.extraSmall : 0)) : (implicitHeight + (hasWindows ? Tokens.padding.extraSmall : 0))

    readonly property int ws: groupOffset + index + 1
    readonly property bool isOccupied: occupied[ws] ?? false
    readonly property bool hasWindows: isOccupied && Config.bar.workspaces.showWindows && (Config.bar.workspaces.maxWindowIcons > 0)
    readonly property bool focused: activeWsId === ws

    // Reveal system for hiding unoccupied workspaces
    readonly property real revealProgress: Math.max(0, Math.min(1, reveal))
    readonly property bool revealTransitionRunning: revealAnimation.running
    readonly property real precedingRevealProgress: {
        let progress = 0;

        for (let i = 0; i < index; ++i) {
            const workspace = workspaceRepeater.itemAt(i) as Workspace;
            if (workspace)
                progress = Math.max(progress, workspace.revealProgress);
        }

        return progress;
    }
    readonly property real targetY: {
        let offset = 0;

        for (let i = 0; i < index; ++i) {
            const workspace = workspaceRepeater.itemAt(i) as Workspace;
            if (workspace?.shouldShow)
                offset += workspace.size + layoutSpacing;
        }

        return offset;
    }
    // Horizontal equivalent of targetY, used by the active indicator
    readonly property real targetX: targetY

    property real reveal: shouldShow ? 1 : 0
    property real animatedSize: size

    function updateShape(): void {
        const shape = indicator.item as MaterialShape;
        if (!shape)
            return;

        if (focused)
            shape.shape = focusedShapeList[Math.floor(Math.random() * focusedShapeList.length)];
        else
            shape.shape = Qt.binding(() => isOccupied ? MaterialShape.Square : MaterialShape.Circle);
    }

    readonly property list<int> focusedShapeList: [MaterialShape.Slanted, MaterialShape.Oval, MaterialShape.Pill, MaterialShape.Triangle, MaterialShape.Arrow, MaterialShape.Diamond, MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.VerySunny, MaterialShape.Sunny, MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided, MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided, MaterialShape.Cookie12Sided, MaterialShape.Clover4Leaf, MaterialShape.SoftBurst, MaterialShape.Ghostish]

    columns: isHorizontal ? -1 : 1
    rows: isHorizontal ? 1 : -1
    flow: isHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom

    Layout.alignment: isHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter
    Layout.preferredWidth: isHorizontal ? animatedSize * revealProgress : -1
    Layout.preferredHeight: isHorizontal ? -1 : animatedSize * revealProgress
    Layout.topMargin: isHorizontal ? 0 : layoutSpacing * Math.min(revealProgress, precedingRevealProgress)
    Layout.leftMargin: isHorizontal ? layoutSpacing * Math.min(revealProgress, precedingRevealProgress) : 0

    visible: shouldShow || revealProgress > 0
    opacity: revealProgress
    clip: true

    columnSpacing: 0
    rowSpacing: 0

    onFocusedChanged: updateShape()
    Component.onCompleted: updateShape()

    Loader {
        id: indicator

        Layout.alignment: isHorizontal ? (Qt.AlignVCenter | Qt.AlignLeft) : (Qt.AlignHCenter | Qt.AlignTop)
        Layout.preferredWidth: isHorizontal ? (Tokens.sizes.bar.innerWidth - Tokens.padding.small) : -1
        Layout.preferredHeight: isHorizontal ? -1 : (Tokens.sizes.bar.innerWidth - Tokens.padding.small)

        asynchronous: true
        // useIcon (fork): the animated material icon indicator;
        // otherwise upstream's displayType decides between text and plain shapes.
        sourceComponent: Config.bar.workspaces.useIcon ? iconComponent : Config.bar.workspaces.displayType === BarWorkspaceDisplay.Text ? textComponent : shapeComponent

        onItemChanged: root.updateShape()
    }

    Component {
        id: shapeComponent

        MaterialShape {
            implicitSize: Tokens.sizes.bar.innerWidth - Tokens.padding.small

            color: Config.bar.workspaces.occupiedBg || root.isOccupied || root.focused ? Colours.palette.m3onSurface : Colours.layer(Colours.palette.m3outlineVariant, 2)
            scale: root.focused ? 2 / 3 : root.isOccupied ? 1 / 3 : 1 / 4

            animationEasing: Tokens.anim.expressiveDefaultSpatial
            animationDuration: Tokens.anim.durations.expressiveDefaultSpatial * Tokens.anim.durations.scale

            Behavior on color {
                CAnim {}
            }

            Behavior on scale {
                Anim {}
            }
        }
    }

    Component {
        id: textComponent

        StyledText {
            animate: true
            text: {
                if (root.focused) {
                    const label = Config.bar.workspaces.activeLabel;
                    if (label)
                        return label;
                }

                if (root.focused || root.isOccupied) {
                    const label = Config.bar.workspaces.occupiedLabel;
                    if (label)
                        return label;
                }

                const label = Config.bar.workspaces.label;
                if (label)
                    return label;

                const ws = Hypr.workspaces.values.find(w => w.id === root.ws);
                const wsName = !ws || ws.name == root.ws ? root.ws : ws.name[0];

                const capitalisation = Config.bar.workspaces.capitalisation;
                if (capitalisation === BarWorkspaceCapitalisation.Upper)
                    return wsName.toString().toUpperCase();
                else if (capitalisation === BarWorkspaceCapitalisation.Lower)
                    return wsName.toString().toLowerCase();
                return wsName;
            }
            color: Config.bar.workspaces.occupiedBg || root.isOccupied || root.focused ? Colours.palette.m3onSurface : Colours.layer(Colours.palette.m3outlineVariant, 2)
            verticalAlignment: Qt.AlignVCenter
            font.family: Tokens.font.workspaces
        }
    }

    Component {
        id: iconComponent

        Item {
            id: iconRoot

            // Track if this position was active (independent of which workspace)
            readonly property bool active: root.activeWsId === root.ws
            property int randShape: MaterialShape.Slanted
            property bool wasPositionActive: false
            property int lastKnownWs: -1
            property int prevActiveWsId: -1

            // Track the previous workspace at this position (before current change)
            property int prevWs: -1

            // Watch for workspace ID changes while inactive by using a binding
            property int watchedWs: root.ws

            // Track the last watched ws separately for detecting changes
            property int lastWatchedWs: -1

            // JavaScript functions
            function handleActivation() {
                const wsChanged = lastKnownWs !== root.ws;
                if (active && (!wasPositionActive || wsChanged)) {
                    const shapes = [MaterialShape.Slanted, MaterialShape.Arch, MaterialShape.Oval, MaterialShape.Pill, MaterialShape.Triangle, MaterialShape.Arrow, MaterialShape.Diamond, MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.VerySunny, MaterialShape.Sunny, MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided, MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided, MaterialShape.Cookie12Sided, MaterialShape.Clover4Leaf, MaterialShape.Clover8Leaf, MaterialShape.SoftBurst, MaterialShape.Ghostish];
                    const shuffled = [...shapes].sort(() => Math.random() - 0.5);
                    randShape = shuffled[0];
                    wsShape.shape = randShape;
                    wsShape.scale = 1 / 3;
                    deactivateAnim.stop();
                    activateAnim.fromValue = 1 / 3;
                    activateAnim.toValue = 2 / 3;
                    activateAnim.running = true;
                } else if (!active && (wasPositionActive || wsChanged)) {
                    const targetShape = root.isOccupied ? MaterialShape.Square : MaterialShape.Circle;
                    wsShape.shape = targetShape;
                    wsShape.scale = 1 / 3;
                    activateAnim.stop();
                    deactivateAnim.stop();
                }
                wasPositionActive = active;
                prevWs = lastKnownWs;
                lastKnownWs = root.ws;
                prevActiveWsId = root.activeWsId;
            }

            // Signal handlers
            onWatchedWsChanged: {
                if (lastWatchedWs !== -1 && watchedWs !== lastWatchedWs && !active) {
                    activateAnim.stop();
                    deactivateAnim.stop();
                    wsShape.shape = root.isOccupied ? MaterialShape.Square : MaterialShape.Circle;
                    wsShape.scale = 1 / 3;
                }
                lastWatchedWs = watchedWs;
            }

            onPrevActiveWsIdChanged: {
                if (prevActiveWsId !== -1 && prevActiveWsId !== root.activeWsId && active) {
                    handleActivation();
                }
            }

            onActiveChanged: handleActivation()

            // Bindings
            implicitWidth: Tokens.sizes.bar.innerWidth - Tokens.padding.small
            implicitHeight: Tokens.sizes.bar.innerWidth - Tokens.padding.small

            // Initialize state when component is created
            Component.onCompleted: {
                if (active) {
                    handleActivation();
                } else {
                    wsShape.shape = root.isOccupied ? MaterialShape.Square : MaterialShape.Circle;
                }
                wasPositionActive = active;
                prevWs = -1;
                lastKnownWs = root.ws;
                prevActiveWsId = root.activeWsId;
                lastWatchedWs = root.ws;
            }

            MaterialShape {
                id: wsShape

                anchors.centerIn: parent
                implicitSize: iconRoot.width
                scale: iconRoot.active ? 2 / 3 : 1 / 3
                color: Config.bar.workspaces.occupiedBg || root.isOccupied || root.activeWsId === root.ws ? Colours.palette.m3onSurface : Colours.layer(Colours.palette.m3outlineVariant, 2)

                Behavior on color {
                    CAnim {}
                }

                Behavior on scale {
                    enabled: !activateAnim.running && !deactivateAnim.running

                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                SequentialAnimation {
                    id: activateAnim

                    property real fromValue: 1 / 3
                    property real toValue: 2 / 3

                    Anim {
                        target: wsShape
                        property: "scale"
                        from: activateAnim.fromValue
                        to: activateAnim.toValue
                        type: Anim.FastSpatial
                    }
                }

                SequentialAnimation {
                    id: deactivateAnim

                    property real fromValue: 2 / 3
                    property real toValue: 1 / 3

                    Anim {
                        target: wsShape
                        property: "scale"
                        from: deactivateAnim.fromValue
                        to: deactivateAnim.toValue
                        type: Anim.FastSpatial
                    }
                }
            }
        }
    }

    Loader {
        id: windows

        asynchronous: true

        Layout.alignment: isHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter
        Layout.fillWidth: isHorizontal && enabled
        Layout.fillHeight: !isHorizontal && enabled
        Layout.topMargin: isHorizontal ? 0 : -Tokens.sizes.bar.innerWidth / 10
        Layout.leftMargin: isHorizontal ? -Tokens.sizes.bar.innerWidth / 10 : 0

        visible: active
        active: root.hasWindows

        sourceComponent: isHorizontal ? rowComponent : columnComponent
    }

    Component {
        id: columnComponent

        Column {
            spacing: 0

            add: Transition {
                Anim {
                    properties: "scale"
                    from: 0
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
            }

            move: Transition {
                Anim {
                    properties: "scale"
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    properties: "x,y"
                }
            }

            Repeater {
                model: ScriptModel {
                    values: {
                        const ws = root.ws;
                        const windows = Hypr.toplevels.values.filter(c => c.workspace?.id === ws);
                        const maxIcons = root.Config.bar.workspaces.maxWindowIcons;
                        return maxIcons > 0 ? windows.slice(0, maxIcons) : windows;
                    }
                }

                MaterialIcon {
                    required property var modelData

                    grade: 0
                    text: Icons.getAppCategoryIcon(modelData.lastIpcObject.class, "terminal")
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }

    Component {
        id: rowComponent

        Row {
            spacing: 0

            add: Transition {
                Anim {
                    properties: "scale"
                    from: 0
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
            }

            move: Transition {
                Anim {
                    properties: "scale"
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    properties: "x,y"
                }
            }

            Repeater {
                model: ScriptModel {
                    values: {
                        const windows = Hypr.toplevelsForWs(root.ws);
                        const maxIcons = root.Config.bar.workspaces.maxWindowIcons;
                        return maxIcons > 0 ? windows.slice(0, maxIcons) : windows;
                    }
                }

                MaterialIcon {
                    required property var modelData

                    grade: 0
                    text: Icons.getAppCategoryIcon(modelData.lastIpcObject.class, "terminal")
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }

    Behavior on animatedSize {
        Anim {}
    }

    Behavior on reveal {
        Anim {
            id: revealAnimation

            type: Anim.DefaultEffects
        }
    }
}
