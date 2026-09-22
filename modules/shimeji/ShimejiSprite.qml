import QtQuick
import Caelestia.Config
import qs.services

Item {
    id: root

    required property var screenSize
    required property var borderThickness
    required property string imgPath
    property real floorOffset: 0

    readonly property real floorY: screenSize.height - 128 - borderThickness - floorOffset
    readonly property real minX: 0
    readonly property real maxX: screenSize.width - 128
    readonly property real maxY: screenSize.height - 128 - floorOffset

    property real vx: 0
    property real vy: 0
    readonly property real gravity: 2

    property bool onGround: false
    property bool dragging: false
    property bool climbing: false
    property point dragOffset
    property real lastX: 0
    property real lastY: 0
    property real dragVx: 0
    property real dragVy: 0
    property int walkTarget: -1

    property string currentAnim: "idle"
    property int frameIndex: 0
    property bool facingRight: true

    // Frame tables for the standard 46-image shimeji layout
    // (pusheen + the default cat pack both ship shime1..shime46)
    readonly property var anims: ({
        idle: ["shime1.png"],
        look: ["shime22.png", "shime1.png"],
        walk: ["shime2.png", "shime1.png", "shime3.png", "shime1.png"],
        lieDown: ["shime18.png", "shime19.png"],
        sleep: ["shime20.png", "shime21.png"],
        dream: ["shime20.png", "shime26.png", "shime27.png", "shime28.png", "shime29.png", "shime21.png"],
        snack: ["shime15.png", "shime16.png", "shime17.png", "shime16.png"],
        munch: ["shime30.png", "shime31.png", "shime32.png", "shime33.png", "shime31.png"],
        mew: ["shime38.png", "shime39.png", "shime40.png", "shime41.png"],
        hang: ["shime13.png", "shime14.png"],
        climb: ["shime13.png", "shime14.png"],
        fall: ["shime4.png", "shime7.png", "shime9.png", "shime10.png"],
        tumble: ["shime4.png", "shime37.png"],
        land: ["shime19.png"]
    })

    function animFrame(anim, index) {
        const list = anims[anim];
        return list ? list[index % list.length] : "";
    }

    function animInterval(anim) {
        if (anim === "walk")
            return 150;
        if (anim === "fall" || anim === "tumble")
            return 120;
        if (anim === "sleep" || anim === "dream")
            return 500;
        if (anim === "snack" || anim === "munch")
            return 250;
        return 220;
    }

    function pickIdle() {
        const roll = Math.random();
        if (roll < 0.35)
            currentAnim = "idle";
        else if (roll < 0.5)
            currentAnim = "look";
        else if (roll < 0.7)
            currentAnim = "lieDown";
        else if (roll < 0.85)
            currentAnim = "sleep";
        else
            currentAnim = "mew";
        frameIndex = 0;
    }

    function walkRandom() {
        const margin = 100;
        walkTarget = margin + Math.random() * (screenSize.width - 128 - margin * 2);
        currentAnim = "walk";
        facingRight = walkTarget > root.x;
        frameIndex = 0;
    }

    // Walk to the nearest screen edge, then ascend it and hang from the top
    function startClimb() {
        const nearLeft = root.x + 64 < screenSize.width / 2;
        walkTarget = nearLeft ? 10 : maxX - 10;
        facingRight = !nearLeft;
        climbing = true;
        currentAnim = "walk";
        frameIndex = 0;
    }

    function hop() {
        onGround = false;
        vy = -6 - Math.random() * 3;
        vx = (Math.random() - 0.5) * 6;
        currentAnim = "tumble";
        frameIndex = 0;
    }

    function tick(dt) {
        if (dragging)
            return;

        const timeScale = dt / 0.030;

        if (!onGround && !climbing) {
            vy += gravity * timeScale;
            vx *= Math.pow(0.98, timeScale);

            // Airborne: tumble frames while fast, plain fall frames otherwise
            if (Math.abs(vy) > 6 || Math.abs(vx) > 6) {
                if (currentAnim !== "tumble" && currentAnim !== "fall") {
                    currentAnim = "tumble";
                    frameIndex = 0;
                }
            } else if (currentAnim !== "fall" && currentAnim !== "land") {
                currentAnim = "fall";
                frameIndex = 0;
            }
        }

        if (walkTarget >= 0) {
            const dx = walkTarget - root.x;
            if (Math.abs(dx) < 8) {
                walkTarget = -1;
                vx = 0;

                if (climbing) {
                    // Reached the edge: start ascending
                    currentAnim = "climb";
                    frameIndex = 0;
                    vy = -2.5;
                    onGround = false;
                } else {
                    pickIdle();
                }
            } else {
                vx = Math.sign(dx) * 2.5;
                facingRight = vx > 0;
                if (currentAnim !== "walk") {
                    currentAnim = "walk";
                    frameIndex = 0;
                }
            }
        }

        if (climbing && walkTarget < 0) {
            root.y += vy * timeScale;
            root.x = facingRight ? maxX : minX;

            if (root.y <= 8) {
                // Reached the top: hang for a moment, then drop back down
                root.y = 8;
                climbing = false;
                currentAnim = "hang";
                frameIndex = 0;
                dropTimer.restart();
                return;
            }

            return;
        }

        root.x += vx * timeScale;
        root.y += vy * timeScale;

        if (root.x < minX) {
            root.x = minX;
            vx = Math.abs(vx) * 0.9;
        } else if (root.x > maxX) {
            root.x = maxX;
            vx = -Math.abs(vx) * 0.9;
        }

        if (root.y > floorY) {
            root.y = floorY;
            vy = -vy * 0.6;
            if (vy >= 0 && Math.abs(vy) < 2) {
                vy = 0;
                onGround = true;
                vx = 0;
                climbing = false;
                currentAnim = "land";
                frameIndex = 0;
                landTimer.restart();
                if (walkTarget < 0 && Math.random() < 0.1 * timeScale)
                    walkRandom();
            } else if (vy < 0) {
                onGround = false;
            }
        } else if (root.y < 0) {
            root.y = 0;
            vy = Math.abs(vy) * 0.6;
        }
    }

    x: 0
    y: floorY
    width: 128
    height: 128

    Component.onCompleted: {
        const margin = 50;
        x = margin + Math.random() * (screenSize.width - 128 - margin * 2);
        y = floorY;
        onGround = true;
        vx = 0;
        vy = 0;
        pickIdle();
    }

    onDraggingChanged: {
        if (dragging) {
            currentAnim = "hang";
            frameIndex = 0;
        } else {
            vx = Math.max(-20, Math.min(20, dragVx * 2));
            vy = Math.max(-20, Math.min(20, dragVy * 2));
            if (Math.abs(vx) < 1)
                vx = 0;
            if (Math.abs(vy) < 1)
                vy = 0;
            climbing = false;
            walkTarget = -1;
            onGround = false;
            currentAnim = Math.abs(vy) + Math.abs(vx) > 10 ? "tumble" : "fall";
            frameIndex = 0;
        }
    }

    MouseArea {
        id: grabArea

        // The visible body of the standard shimeji layout sits at roughly
        // x 4-125, y 44-128 inside the 128px canvas — match the grab area to it
        x: 4
        y: 40
        width: 120
        height: 88
        hoverEnabled: false
        propagateComposedEvents: true
        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        acceptedButtons: Qt.LeftButton

        onPressed: mouse => {
            dragging = true;
            walkTarget = -1;
            climbing = false;
            dropTimer.stop();
            landTimer.stop();
            dragOffset = Qt.point(mouse.x, mouse.y);
            lastX = root.x;
            lastY = root.y;
            dragVx = 0;
            dragVy = 0;
            vx = 0;
            vy = 0;
        }

        onPositionChanged: mouse => {
            if (dragging) {
                const newX = Math.max(minX, Math.min(maxX, root.x + mouse.x - dragOffset.x));
                const newY = Math.max(0, Math.min(maxY, root.y + mouse.y - dragOffset.y));
                dragVx = newX - lastX;
                dragVy = newY - lastY;
                lastX = newX;
                lastY = newY;
                root.x = newX;
                root.y = newY;
            }
        }

        onReleased: dragging = false
    }

    Image {
        id: spriteImage

        anchors.fill: parent
        source: {
            const fn = root.animFrame(root.currentAnim, root.frameIndex);
            return fn ? "file://" + root.imgPath + fn : "";
        }
        sourceSize.width: 128
        sourceSize.height: 128
        fillMode: Image.PreserveAspectFit

        mirror: root.facingRight
    }

    FrameAnimation {
        id: physicsLoop

        running: true
        onTriggered: root.tick(frameTime)
    }

    Timer {
        id: animTimer

        interval: root.animInterval(root.currentAnim)
        repeat: true
        running: true
        onTriggered: {
            if (!root.dragging)
                root.frameIndex++;
        }
    }

    // Ends a hover-at-the-ceiling after a moment, dropping back to the floor
    Timer {
        id: dropTimer

        interval: 1500 + Math.random() * 2000
        onTriggered: {
            if (!root.dragging) {
                root.onGround = false;
                root.climbing = false;
                root.vy = 1;
                root.vx = (Math.random() < 0.5 ? -1 : 1) * (2 + Math.random() * 2);
                root.currentAnim = "fall";
                root.frameIndex = 0;
            }
        }
    }

    // Brief loaf pose on landing, then back to idle picks
    Timer {
        id: landTimer

        interval: 500
        onTriggered: {
            if (root.onGround && !root.dragging)
                root.pickIdle();
        }
    }

    Timer {
        id: behaviorTimer

        interval: 3000 + Math.random() * 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            // Re-roll the period so the loop doesn't become metronomic
            interval = 3000 + Math.random() * 5000;

            if (root.dragging || !root.onGround || root.walkTarget >= 0 || root.climbing)
                return;

            if (Math.abs(root.vx) >= 0.5)
                return;

            const roll = Math.random();
            if (roll < 0.2) {
                root.pickIdle();
            } else if (roll < 0.42) {
                root.walkRandom();
            } else if (roll < 0.52) {
                root.currentAnim = "snack";
                root.frameIndex = 0;
            } else if (roll < 0.6) {
                root.currentAnim = "dream";
                root.frameIndex = 0;
            } else if (roll < 0.68) {
                root.currentAnim = "mew";
                root.frameIndex = 0;
            } else if (roll < 0.76) {
                root.currentAnim = "lieDown";
                root.frameIndex = 0;
            } else if (roll < 0.84) {
                root.currentAnim = "sleep";
                root.frameIndex = 0;
            } else if (roll < 0.94) {
                root.startClimb();
            } else {
                root.hop();
            }
        }
    }
}
