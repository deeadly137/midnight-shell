pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property alias running: props.running
    readonly property alias paused: props.paused
    readonly property alias elapsed: props.elapsed
    property int refCount: 0
    property bool needsStart
    property list<string> startArgs
    property bool needsStop
    property bool needsPause

    function start(extraArgs = []): void {
        needsStart = true;
        startArgs = extraArgs;
        checkProc.running = true;
    }

    function stop(): void {
        needsStop = true;
        checkProc.running = true;
    }

    function togglePause(): void {
        needsPause = true;
        checkProc.running = true;
    }

    PersistentProperties {
        id: props

        property bool running: false
        property bool paused: false
        property real elapsed: 0 // Might get too large for int

        reloadableId: "recorder"
    }

    Process {
        id: checkProc

        running: true
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => { // qmllint disable signal-handler-parameters
            const running = code === 0;

            if (running && root.needsStop) {
                // Detached: the stop CLI blocks until its toast buttons are
                // clicked, and must not hold commandProc (a pending start
                // would be lost). The poll reconciles the real state.
                Quickshell.execDetached(["caelestia", "record"]);
                props.running = false;
                props.paused = false;
                Audio.playVideoStop();
            } else if (running && root.needsPause) {
                Quickshell.execDetached(["caelestia", "record", "-p"]);
                props.paused = !props.paused;
            } else if (!running && root.needsStart) {
                commandProc.exec(["caelestia", "record", ...root.startArgs]);
                props.running = true;
                props.paused = false;
                props.elapsed = 0;
                Audio.playVideoRecord();
            } else if (running !== props.running && !commandProc.running) {
                // The recording was started/stopped outside the shell (e.g. via
                // keybind), or our command finished without reaching the optimistic state
                props.running = running;
                props.paused = false;
                props.elapsed = 0;
            }

            root.needsStart = false;
            root.needsStop = false;
            root.needsPause = false;
        }
    }

    Process {
        id: commandProc

        // Never hand our stdin pipe down the chain: `caelestia record -r`
        // spawns slurp, which has been observed hanging forever while reading
        // an inherited, never-written pipe instead of showing its UI.
        stdinEnabled: false

        // The command owns the start transition: `caelestia record -r` blocks
        // on slurp for region captures. Reconcile once it has finished.
        onExited: checkProc.running = true // qmllint disable signal-handler-parameters
    }

    // Only poll while something is showing the state, i.e. the utilities drawer is open
    Timer {
        interval: 1000
        running: root.refCount > 0
        repeat: true
        triggeredOnStart: true

        onTriggered: checkProc.running = true
    }

    Connections {
        enabled: props.running && !props.paused
        function onSecondsChanged(): void {
            props.elapsed++;
        }

        target: Time // qmllint disable incompatible-type
    }
}
