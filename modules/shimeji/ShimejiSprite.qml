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
    property int dragPose: 0
    property bool climbing: false
    property bool ceilingWalk: false
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
    // 1-3 walk · 4 fall · 5-10 drag poses (H-up, H-down, diag-up, diag-down,
    // steep-up, steep-down) · 11 idle · 12-14 climb · 15-17 ice cream ·
    // 18/21 saddened flat · 19 sit happy · 20/24 neutral flat · 22 stand happy ·
    // 23-25 ceiling walk · 26-29 pizza thought · 30-33 chicken · 34-36 window
    // grab · 37 jump away · 38-41 donut · 42-46 placeholders
    readonly property var anims: ({
        walk: ["shime1.png", "shime2.png", "shime3.png"],
        fall: ["shime4.png"],
        drag: ["shime5.png", "shime6.png", "shime7.png", "shime8.png", "shime9.png", "shime10.png"],
        idle: ["shime11.png"],
        climb: ["shime12.png", "shime13.png", "shime14.png"],
        snack: ["shime15.png", "shime16.png", "shime17.png"],
        sad: ["shime18.png", "shime21.png"],
        sit: ["shime19.png"],
        flat: ["shime20.png"],
        happy: ["shime22.png"],
        ceiling: ["shime23.png", "shime24.png", "shime25.png"],
        pizza: ["shime26.png", "shime27.png", "shime28.png", "shime29.png"],
        munch: ["shime30.png", "shime31.png", "shime32.png", "shime33.png"],
        grab: ["shime34.png", "shime35.png", "shime36.png"],
        jump: ["shime37.png"],
        land: ["shime20.png"],
        donut: ["shime38.png", "shime39.png", "shime40.png", "shime41.png"]
    })

    // Per-frame opaque bounding boxes: [x, y, w, h] inside the 128px canvas
    // (measured from the alpha channel of the default pack; mirror-aware
    // consumers recompute x). Empty frames fall back to the body rect.
    readonly property var frameBoxes: ({
        "shime1.png": [4, 53, 121, 73],
        "shime2.png": [8, 49, 120, 75],
        "shime3.png": [5, 51, 120, 73],
        "shime4.png": [6, 0, 97, 126],
        "shime5.png": [9, 47, 116, 78],
        "shime6.png": [5, 50, 117, 74],
        "shime7.png": [11, 37, 112, 89],
        "shime8.png": [5, 46, 110, 78],
        "shime9.png": [21, 31, 98, 89],
        "shime10.png": [7, 30, 101, 91],
        "shime11.png": [30, 35, 77, 91],
        "shime12.png": [55, 8, 73, 116],
        "shime13.png": [55, 10, 73, 115],
        "shime14.png": [57, 9, 71, 115],
        "shime15.png": [26, 34, 82, 93],
        "shime16.png": [26, 34, 82, 93],
        "shime17.png": [26, 33, 82, 95],
        "shime18.png": [3, 74, 122, 54],
        "shime19.png": [18, 53, 92, 74],
        "shime20.png": [3, 78, 122, 50],
        "shime21.png": [3, 29, 121, 99],
        "shime22.png": [4, 53, 121, 73],
        "shime23.png": [4, 47, 121, 73],
        "shime24.png": [5, 49, 120, 75],
        "shime25.png": [4, 48, 120, 73],
        "shime26.png": [24, 0, 77, 128],
        "shime27.png": [24, 0, 77, 128],
        "shime28.png": [24, 0, 77, 128],
        "shime29.png": [24, 0, 77, 128],
        "shime30.png": [22, 29, 92, 95],
        "shime31.png": [23, 31, 85, 96],
        "shime32.png": [22, 28, 93, 98],
        "shime33.png": [24, 35, 95, 86],
        "shime34.png": [28, 19, 93, 103],
        "shime35.png": [25, 19, 96, 103],
        "shime36.png": [25, 19, 96, 103],
        "shime37.png": [21, 16, 101, 107],
        "shime38.png": [10, 32, 99, 93],
        "shime39.png": [7, 35, 103, 91],
        "shime40.png": [10, 32, 99, 93],
        "shime41.png": [8, 36, 101, 91],
        "shime42.png": [9, 54, 116, 73],
        "shime43.png": [9, 55, 109, 71],
        "shime44.png": [9, 54, 116, 73],
        "shime45.png": [10, 54, 106, 74],
        "shime46.png": [15, 36, 110, 91]
    })

    function animFrame(anim, index) {
        const list = anims[anim];
        return list ? list[index % list.length] : "";
    }

    function animInterval(anim) {
        if (anim === "walk" || anim === "ceiling")
            return 140;
        if (anim === "climb")
            return 160;
        if (anim === "fall" || anim === "jump")
            return 100;
        if (anim === "snack" || anim === "munch" || anim === "donut" || anim === "grab")
            return 260;
        if (anim === "pizza")
            return 320;
        return 240;
    }

    // The drag pose roughly matching the cursor's velocity direction
    // (index into the drag table: 0=shime5 H-up, 1=shime6 H-down,
    //  2=shime7 diag-up, 3=shime8 diag-down, 4=shime9 steep-up, 5=shime10 steep-down)
    function dragPoseFor(vx, vy) {
        const speed = Math.abs(vx) + Math.abs(vy);
        if (speed < 4)
            return 0; // barely moving: hang horizontally, slightly upwards
        const angle = Math.atan2(-vy, Math.abs(vx)) * 180 / Math.PI; // up = positive
        if (angle > 50)
            return 4;
        if (angle > 22)
            return 2;
        if (angle >= 0)
            return 0;
        if (angle > -22)
            return 1;
        if (angle > -50)
            return 3;
        return 5;
    }

    // Pick a random idle pose (11 idle, 22 standing happy, 19 sitting happy,
    // 20 neutral flat, 18/21 saddened flat)
    function pickIdle() {
        const roll = Math.random();
        if (roll < 0.25)
            currentAnim = "idle";
        else if (roll < 0.45)
            currentAnim = "happy";
        else if (roll < 0.65)
            currentAnim = "sit";
        else if (roll < 0.8)
            currentAnim = "flat";
        else
            currentAnim = "sad";
        frameIndex = 0;
    }

    function startSnack() {
        const roll = Math.random();
        if (roll < 0.4)
            currentAnim = "snack";
        else if (roll < 0.7)
            currentAnim = "munch";
        else
            currentAnim = "donut";
        frameIndex = 0;
    }

    function walkRandom() {
        const margin = 100;
        walkTarget = margin + Math.random() * (screenSize.width - 128 - margin * 2);
        currentAnim = "walk";
        facingRight = walkTarget > root.x;
        frameIndex = 0;
    }

    // Walk to the nearest screen edge, climb the wall, then walk the ceiling
    function startClimb() {
        const nearLeft = root.x + 64 < screenSize.width / 2;
        walkTarget = nearLeft ? 10 : maxX - 10;
        facingRight = !nearLeft;
        climbing = true;
        ceilingWalk = false;
        currentAnim = "walk";
        frameIndex = 0;
    }

    function hop() {
        onGround = false;
        vy = -7 - Math.random() * 3;
        vx = (Math.random() - 0.5) * 6;
        currentAnim = "jump";
        frameIndex = 0;
    }

    function tick(dt) {
        if (dragging)
            return;

        const timeScale = dt / 0.030;

        // Climbing the wall (12-14): pinned to the edge, ascending
        if (climbing) {
            root.y += vy * timeScale;
            root.x = facingRight ? maxX : minX;

            if (root.y <= 8) {
                root.y = 8;
                climbing = false;
                ceilingWalk = true;
                walkTarget = 60 + Math.random() * (screenSize.width - 240);
                currentAnim = "ceiling";
                frameIndex = 0;
            }
            return;
        }

        // Walking along the ceiling (23-25), then dropping off
        if (ceilingWalk) {
            if (walkTarget < 0) {
                ceilingWalk = false;
                onGround = false;
                vy = 2;
                vx = 0;
                currentAnim = "jump";
                frameIndex = 0;
                return;
            }

            const dx = walkTarget - root.x;
            if (Math.abs(dx) < 6) {
                walkTarget = -1;
                ceilingWalk = false;
                onGround = false;
                vy = 2;
                vx = (Math.random() < 0.5 ? -1 : 1) * (1.5 + Math.random() * 2);
                currentAnim = "jump";
                frameIndex = 0;
                return;
            }

            vx = Math.sign(dx) * 1.5;
            facingRight = vx > 0;
            root.x = Math.max(minX, Math.min(maxX, root.x + vx * timeScale));
            return;
        }

        // Airborne: gravity, fall frame (4) or jump frame (37) while rising
        if (!onGround) {
            vy += gravity * timeScale;
            vx *= Math.pow(0.98, timeScale);
            if (vy > 0 && currentAnim !== "fall") {
                currentAnim = "fall";
                frameIndex = 0;
            }
        }

        if (walkTarget >= 0) {
            const dx = walkTarget - root.x;
            if (Math.abs(dx) < 8) {
                walkTarget = -1;
                vx = 0;
                pickIdle();
            } else {
                vx = Math.sign(dx) * 2.5;
                facingRight = vx > 0;
                if (currentAnim !== "walk") {
                    currentAnim = "walk";
                    frameIndex = 0;
                }
            }
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
            if (Math.abs(vy) > 3) {
                // Bounce, shedding half the speed each hit (always terminates)
                vy = -Math.abs(vy) * 0.5;
            } else {
                vy = 0;
                vx = 0;
                if (!onGround) {
                    onGround = true;
                    currentAnim = "land";
                    frameIndex = 0;
                    landTimer.restart();
                    if (Math.random() < 0.15 * timeScale)
                        walkRandom();
                }
            }
        } else if (root.y < 0) {
            root.y = 0;
            vy = Math.abs(vy) * 0.5;
        }
    }

    x: 0
    y: floorY
    width: 128
    height: 128

    // The opaque bounding box of the frame currently displayed, mirror-adjusted
    readonly property string frameFile: animFrame(currentAnim, frameIndex)
    readonly property var frameBox: frameBoxes[frameFile] ?? [30, 35, 77, 91]
    readonly property real boxX: dragging ? 0 : (facingRight ? 128 - frameBox[0] - frameBox[2] : frameBox[0])
    readonly property real boxY: dragging ? 0 : frameBox[1]
    readonly property real boxW: dragging ? 128 : frameBox[2]
    readonly property real boxH: dragging ? 128 - frameBox[1] : frameBox[3]

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
            currentAnim = "drag";
            frameIndex = dragPose;
        } else {
            climbing = false;
            ceilingWalk = false;
            walkTarget = -1;
            vx = Math.max(-20, Math.min(20, dragVx * 2));
            vy = Math.max(-20, Math.min(20, dragVy * 2));
            if (Math.abs(vx) < 1)
                vx = 0;
            if (Math.abs(vy) < 1)
                vy = 0;
            onGround = false;
            currentAnim = vy < -2 ? "jump" : "fall";
            frameIndex = 0;
        }
    }

    MouseArea {
        id: grabArea

        // Hitbox exactly matches the opaque area of the displayed frame
        // (mirror-adjusted). While dragging it expands to the full canvas so
        // mid-drag frame changes cannot shift the pointer math.
        x: root.boxX
        y: root.boxY
        width: root.boxW
        height: root.boxH
        hoverEnabled: false
        propagateComposedEvents: true
        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        acceptedButtons: Qt.LeftButton

        onPressed: mouse => {
            // Ignore clicks on transparent pixels of the current frame
            const cx = Math.max(0, Math.min(127, Math.round(mouse.x)));
            const cy = Math.max(0, Math.min(127, Math.round(mouse.y)));
            const sx = root.facingRight ? 127 - cx : cx;
            const data = maskCanvas.context.getImageData(sx, cy, 1, 1).data;
            if (data[3] < 20) {
                mouse.accepted = false;
                return;
            }

            dragging = true;
            climbing = false;
            ceilingWalk = false;
            walkTarget = -1;
            landTimer.stop();
            const px = mouse.x + grabArea.x;
            const py = mouse.y + grabArea.y;
            dragOffset = Qt.point(px - root.x, py - root.y);
            lastX = root.x;
            lastY = root.y;
            dragVx = 0;
            dragVy = 0;
            vx = 0;
            vy = 0;
        }

        onPositionChanged: mouse => {
            if (!dragging)
                return;

            const px = mouse.x + grabArea.x;
            const py = mouse.y + grabArea.y;
            const newX = Math.max(minX, Math.min(maxX, px - dragOffset.x));
            const newY = Math.max(0, Math.min(maxY, py - dragOffset.y));
            dragVx = newX - lastX;
            dragVy = newY - lastY;
            lastX = newX;
            lastY = newY;
            root.x = newX;
            root.y = newY;

            // Pose tracks the drag direction (5-10)
            const pose = dragPoseFor(dragVx, dragVy);
            if (Math.abs(dragVx) > 2)
                facingRight = dragVx > 0;
            if (pose !== dragPose) {
                dragPose = pose;
                frameIndex = dragPose;
            }
        }

        onReleased: dragging = false
    }

    // Offscreen copy of the current frame for alpha hit-testing. Kept in the
    // scene (declared under spriteImage) because an invisible Canvas is not
    // guaranteed to paint; the sprite image fully covers it.
    Canvas {
        id: maskCanvas

        anchors.fill: parent
        renderStrategy: Canvas.Immediate
        opacity: 0
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (maskSource.status === Image.Ready)
                ctx.drawImage(maskSource, 0, 0, 128, 128);
        }
    }

    Image {
        id: maskSource

        opacity: 0
        source: root.imgPath + root.frameFile
        sourceSize.width: 128
        sourceSize.height: 128
        cache: true
        onStatusChanged: {
            if (status === Image.Ready)
                maskCanvas.requestPaint();
        }
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

    onCurrentAnimChanged: animTimer.restart()

    // Brief settle pose on landing, then a fresh idle pick
    Timer {
        id: landTimer

        interval: 500
        onTriggered: {
            if (root.onGround && !root.dragging)
                root.pickIdle();
        }
    }

    // The window-grab anim ends with the shimeji jumping away (37)
    Timer {
        id: grabTimer

        interval: 1600
        onTriggered: {
            if (currentAnim !== "grab" || dragging || !onGround)
                return;

            currentAnim = "jump";
            frameIndex = 0;
            onGround = false;
            vy = -5 - Math.random() * 2;
            vx = (Math.random() < 0.5 ? -1 : 1) * 2.5;
        }
    }

    Timer {
        id: behaviorTimer

        interval: 3500 + Math.random() * 4500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            // Re-roll the period so the loop doesn't become metronomic
            interval = 3500 + Math.random() * 4500;

            if (dragging || climbing || ceilingWalk || !onGround)
                return;

            const roll = Math.random();
            if (roll < 0.16) {
                pickIdle();
            } else if (roll < 0.38) {
                walkRandom();
            } else if (roll < 0.48) {
                startSnack();
            } else if (roll < 0.56) {
                currentAnim = "pizza";
                frameIndex = 0;
            } else if (roll < 0.68) {
                startClimb();
            } else if (roll < 0.74) {
                hop();
            } else if (roll < 0.82) {
                currentAnim = "grab";
                frameIndex = 0;
                grabTimer.restart();
            } else {
                currentAnim = "sad";
                frameIndex = 0;
            }
        }
    }
}
