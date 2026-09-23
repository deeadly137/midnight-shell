pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config

// Restarts the shell when a new display is connected. Quickshell surfaces on
// the newly connected screen can fail to appear (only one screen keeps its
// shell), and a full restart — the same one the restart keybind triggers —
// is the reliable workaround.
Scope {
    id: root

    // Hyprland emits monitoradded for outputs that were already present while
    // the shell is starting — ignore events in this window after startup
    readonly property int gracePeriod: 5000
    // The restart itself is asynchronous and takes a few seconds; ignore any
    // further hotplug events until it has fully settled
    readonly property int cooldown: 15000

    property real startedAt: Date.now()
    property bool restartPending: false

    function restart(): void {
        if (restartPending)
            return;

        restartPending = true;
        // The cooldown flag file is guarded inside the detached script so it
        // survives this shell dying during the restart
        Quickshell.execDetached(["sh", "-c", [
            "[ -e /tmp/caelestia-display-restart ] && exit 0",
            "touch /tmp/caelestia-display-restart",
            "caelestia shell -r -d 2>/dev/null || { qs -c caelestia kill; sleep 1; caelestia shell -d; }",
            "sleep 12",
            "rm -f /tmp/caelestia-display-restart"
        ].join("; ")]);
    }

    Component.onCompleted: startedAt = Date.now()

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name !== "monitoradded")
                return;
            if (!GlobalConfig.general.restartOnDisplayChange)
                return;
            if (Date.now() - root.startedAt < root.gracePeriod)
                return;

            root.restart();
        }
    }
}
