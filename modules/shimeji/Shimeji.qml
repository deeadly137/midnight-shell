import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Caelestia.Config
import qs.components.containers
import qs.components
import qs.services
import qs.utils

StyledWindow {
    id: root

    required property ShellScreen modelData
    property int shimejiCount: 1

    readonly property alias shimejiScreen: root.modelData

    readonly property bool shouldBeVisible: !(GameMode.enabled && GlobalConfig.utilities.gameMode.disableShimeji) && (!GlobalConfig.forScreen(modelData.name).shimeji.autoHide || (Hypr.monitorFor(modelData)?.activeWorkspace?.toplevels?.values.every(t => t.lastIpcObject?.floating) ?? true))

    property var extractedPaths: []

    property Process extractor: Process {
        running: false
        command: ["unzip", "-o"]
        workingDirectory: "/tmp"
    }

    readonly property real borderThickness: modelData ? contentItem.Config.border.thickness : 0

    readonly property var barWrapper: (() => {
        let name = root.screen ? root.screen.name : undefined;
        let bar = name ? Visibilities.bars.get(name) : undefined;
        return bar;
    })()

    readonly property real barExclusiveZone: barWrapper?.exclusiveZone ?? (Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness))

    // Reserve the bar's exclusive zone on whichever edge it occupies — computed
    // reactively from Config.bar.position + the bar's live exclusiveZone, so the
    // sprites re-resolve geometry when the config or bar layout changes
    readonly property real floorOffset: Config.bar.position === "bottom" ? barExclusiveZone : 0
    readonly property real ceilingOffset: Config.bar.position === "top" ? barExclusiveZone : 0
    readonly property real leftOffset: Config.bar.position === "left" ? barExclusiveZone : 0
    readonly property real rightOffset: Config.bar.position === "right" ? barExclusiveZone : 0

    function getImgPath(): string {
        if (!modelData)
            return "";
        let path = Paths.absolutePath(String(contentItem.Config.shimeji.path));
        if (!path)
            return "";

        if (path.endsWith(".zip")) {
            const extractDir = path.replace(".zip", "/");
            if (!extractor.running && !extractedPaths.includes(path)) {
                extractedPaths.push(path);
                extractor.arguments = ["-o", "-d", extractDir, path];
                extractor.running = true;
            }
            return extractDir;
        }

        return path.replace(/\/?$/, "/");
    }

    // The window's input mask covers only the sprites — everything outside
    // their rects passes input through to windows, panels and the desktop.
    property list<Region> spriteMasks: []

    mask: Region {
        regions: root.spriteMasks
    }

    function registerSpriteMask(region: Region): void {
        if (!root.spriteMasks.includes(region))
            root.spriteMasks = [...root.spriteMasks, region];
    }

    function unregisterSpriteMask(region: Region): void {
        root.spriteMasks = root.spriteMasks.filter(m => m !== region);
    }

    screen: modelData
    visible: shouldBeVisible

    name: "shimeji"
    // Top layer: the shimeji walks above windows (like the real Shimeji pet).
    // Bottom-layer input routing made grabbing unreliable (clicks competed
    // with regular windows and the fullscreen wallpaper surface).
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    surfaceFormat.opaque: false

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Component.onCompleted: {
        Qt.callLater(() => {
            extractor.running = false;
        });
    }

    Item {
        anchors.fill: parent

        Repeater {
            id: spriteRepeater

            model: root.shimejiCount > 0 ? root.shimejiCount : 1

            ShimejiSprite {
                maskHost: root
                screenSize: Qt.size(shimejiScreen.width, shimejiScreen.height)
                borderThickness: root.borderThickness
                floorOffset: root.floorOffset
                ceilingOffset: root.ceilingOffset
                leftOffset: root.leftOffset
                rightOffset: root.rightOffset
                imgPath: root.getImgPath()
            }
        }
    }
}
