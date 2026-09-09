#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D dataTex;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float itemWidth;
    float itemHeight;
    int barCount;
    float rounding;
    float spacing;
    float dpr;
    vec4 primaryColor;
    vec4 secondaryColor;
};

float sampleBar(int i) {
    if (barCount <= 0) return 0.0;

    int ci = clamp(i, 0, barCount - 1);
    float u = (float(ci) + 0.5) / float(barCount);
    vec2 t = texture(dataTex, vec2(u, 0.5)).rg;
    return clamp(t.x * (256.0 / 255.0) + t.y * (1.0 / 255.0), 0.0, 1.0);
}

void main() {
    if (barCount <= 0 || itemWidth <= 0.0 || itemHeight <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float px = qt_TexCoord0.x * itemWidth;
    float py = qt_TexCoord0.y * itemHeight;

    float sideWidth = itemWidth * 0.4;
    float slotWidth = sideWidth / float(barCount);
    float barWidth = slotWidth - spacing;

    if (barWidth <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    bool isLeft = (px < sideWidth);
    bool isRight = (px >= itemWidth * 0.6 && px <= itemWidth);

    if (!isLeft && !isRight) {
        fragColor = vec4(0.0);
        return;
    }

    float sideOffset = isRight ? (itemWidth * 0.6) : 0.0;
    float localX = px - sideOffset;

    int i = int(floor(localX / slotWidth));
    i = clamp(i, 0, barCount - 1);

    int valueIndex = isRight ? i : (barCount - 1 - i);
    float value = clamp(sampleBar(valueIndex), 0.0, 1.0);

    float maxBarHeight = itemHeight * 0.4;
    float barHeight = value * maxBarHeight;

    if (barHeight <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float barLeft = sideOffset + float(i) * slotWidth;
    float barTop = itemHeight - barHeight;
    float barBottom = itemHeight;

    float halfW = barWidth * 0.5;
    float cx = barLeft + halfW;

    float r = min(min(rounding, halfW), barHeight);

    vec2 p = vec2(abs(px - cx), py);

    float qx = p.x - halfW;
    float qyTop = barTop - p.y;
    float qyBot = p.y - barBottom;

    float dist = max(qx, max(qyTop, qyBot));

    if (r > 0.0 && p.x > (halfW - r) && p.y < (barTop + r)) {
        vec2 cornerCenter = vec2(halfW - r, barTop + r);
        dist = length(p - cornerCenter) - r;
    }

    float alpha = clamp(0.5 - dist * dpr, 0.0, 1.0);

    if (alpha <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float gradT = clamp((py - (itemHeight - maxBarHeight)) / maxBarHeight, 0.0, 1.0);
    vec4 col = mix(primaryColor, secondaryColor, gradT);

    fragColor = col * alpha * qt_Opacity;
}