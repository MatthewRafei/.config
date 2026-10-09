#version 440
// Matrix rain, one fragment per pixel (MatrixRain.qml). Every column is a
// closed-form function of time, so the CPU only advances `time`.
// Adapted from nzkritik/omarchy-matrix-lock (MIT).
//
// Rebuild after editing:
//   /usr/lib64/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//       -o matrix-rain.frag.qsb matrix-rain.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // item size in logical px
    vec2 cell;          // grid pitch in logical px (w, h)
    float time;         // seconds
    float glyphCount;   // glyphs in the atlas row
    float minSpeed;     // rows per second
    float maxSpeed;
    float minTrail;     // glyphs per stream
    float maxTrail;
    float churn;        // glyph swaps per second, per glyph
    vec4 headColor;
    vec4 bodyColor;
    vec4 midColor;
    vec4 tailColor;
};

layout(binding = 1) uniform sampler2D atlas;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// one stream in column `col`; layer offsets the hashes so two layers differ
vec4 stream(vec2 px, float col, float layer) {
    float rows = ceil(size.y / cell.y);
    float speed = mix(minSpeed, maxSpeed, hash(vec2(col, 1.0 + layer)));
    float trail = floor(mix(minTrail, maxTrail + 1.0, hash(vec2(col, 2.0 + layer))));
    float gap = rows * 0.6 * hash(vec2(col, 3.0 + layer));
    float span = rows + trail + gap;
    // random phase: the screen opens already full of rain
    float travel = time * speed + hash(vec2(col, 4.0 + layer)) * span;
    float pass = floor(travel / span);
    float headRow = mod(travel, span) - 1.0;

    // 0 at the tail end, trail-1 at the head
    float local = px.y / cell.y - (headRow - trail + 1.0);
    if (local < 0.0 || local >= trail) return vec4(0.0);
    float j = floor(local);
    float k = j / max(1.0, trail - 1.0);        // 0 tail .. 1 head
    vec4 tint = j >= trail - 1.0 ? headColor
              : k < 0.4 ? mix(vec4(0.0), tailColor, k / 0.4)
              : k < 0.7 ? mix(tailColor, midColor, (k - 0.4) / 0.3)
              : mix(midColor, bodyColor, (k - 0.7) / 0.3);

    // glyphs are fixed to screen rows (the film's look: the stream lights them
    // up as it passes), each flickering on its own schedule
    float row = floor(px.y / cell.y);
    float seed = hash(vec2(col * 7.0 + row, pass + layer * 31.0));
    float flip = floor(time * churn + seed * 97.0);
    float glyph = floor(hash(vec2(seed * 131.0, flip)) * glyphCount);
    // mirrored, as in the film
    vec2 inCell = vec2(1.0 - fract(px.x / cell.x), fract(px.y / cell.y));
    float a = texture(atlas, vec2((glyph + inCell.x) / glyphCount, inCell.y)).a;
    return tint * a;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    float col = floor(px.x / cell.x);
    vec4 c = stream(px, col, 0.0);
    // a second, sparser stream in some columns so the screen never looks gridded
    if (hash(vec2(col, 9.0)) < 0.35) c = max(c, stream(px, col, 1.0));
    fragColor = c * qt_Opacity;
}
