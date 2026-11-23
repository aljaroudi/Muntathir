#include <metal_stdlib>
using namespace metal;

static float skyHash(float2 point) {
    return fract(sin(dot(point, float2(127.1, 311.7))) * 43758.5453f);
}

static float skyNoise(float2 point) {
    float2 cell = floor(point);
    float2 local = fract(point);
    float2 blend = local * local * (3 - 2 * local);
    return mix(mix(skyHash(cell), skyHash(cell + float2(1, 0)), blend.x),
               mix(skyHash(cell + float2(0, 1)), skyHash(cell + float2(1, 1)), blend.x), blend.y);
}

/// Value noise around a circle with `count` cells; any angle works and it wraps seamlessly.
static float angularNoise(float angle, float count, float seed) {
    float x = fract(angle / (2 * M_PI_F)) * count;
    float cell = floor(x);
    float blend = smoothstep(0.0f, 1.0f, fract(x));
    return mix(skyHash(float2(fmod(cell, count), seed)), skyHash(float2(fmod(cell + 1, count), seed)), blend);
}

/// Sun disc with limb darkening, corona and soft rays; the disc spans the middle quarter of `bounds`.
/// `time` should wrap at a multiple of 120 seconds so every motion period stays seamless.
[[ stitchable ]] half4 sunGlow(float2 position, float4 bounds, float elevation, float time) {
    float2 center = bounds.xy + bounds.zw * 0.5f;
    float radius = min(bounds.z, bounds.w) * 0.125f;
    float2 offset = (position - center) / radius;
    float distance = length(offset);
    float outside = max(distance - 1, 0.0f);
    float warmth = 1 - smoothstep(2.0f, 18.0f, elevation);
    float3 coreColor = mix(float3(1.0, 0.97, 0.88), float3(1.0, 0.80, 0.52), warmth);
    float3 glowColor = mix(float3(1.0, 0.80, 0.42), float3(1.0, 0.46, 0.16), warmth);

    // Two counter-rotating ray layers (120 s and 60 s periods) with a 10 s breath.
    float angle = atan2(offset.y, offset.x);
    float turn = 2 * M_PI_F * time;
    float rays = angularNoise(angle + turn / 120, 29, 1) * 0.55f + angularNoise(angle - turn / 60, 41, 2) * 0.45f;
    float breath = 1 + 0.06f * sin(turn / 10);
    float corona = 0.8f * exp(-outside * 3.5f);
    float bloom = 0.45f / (1 + 2.5f * outside * outside);
    float streaks = 0.4f * rays * rays * rays * exp(-outside * 0.9f) * smoothstep(0.0f, 0.3f, outside);
    float glow = (corona + bloom + streaks) * breath * (1 - smoothstep(2.4f, 3.95f, distance));
    glow = clamp(glow, 0.0f, 1.0f);

    float rim = 1 - sqrt(1 - min(distance * distance, 1.0f));
    float3 discColor = mix(coreColor, glowColor, rim * 0.5f) * (1 - 0.12f * rim);
    float edge = 1 - smoothstep(1 - 1.2f / radius, 1 + 1.2f / radius, distance);

    float3 color = mix(glowColor * glow, discColor, edge);
    float alpha = mix(glow, 1.0f, edge);
    return half4(half3(color), half(alpha));
}

/// Soft elliptical mare mask in face coordinates (x right, y down, unit radius).
static float mare(float2 face, float2 center, float2 radii) {
    return 1 - smoothstep(0.2f, 1.05f, length((face - center) / radii));
}

/// Lit moon sphere filling `bounds`.
/// `phase` is the Sun–Moon–Earth phase angle (0 full, π new); `limbAngle` and `northAngle`
/// point the lit limb and lunar north on screen, in radians clockwise from up.
[[ stitchable ]] half4 moonFace(float2 position, float4 bounds, float phase, float limbAngle, float northAngle) {
    float2 center = bounds.xy + bounds.zw * 0.5f;
    float radius = min(bounds.z, bounds.w) * 0.5f;
    float2 point = (position - center) / radius;
    float distance = length(point);
    float edge = 1 - smoothstep(1 - 1.0f / radius, 1 + 0.5f / radius, distance);
    if (edge <= 0) {
        return half4(0);
    }

    // Albedo: near-side maria laid out with lunar north up.
    float2 face = float2(dot(point, float2(cos(northAngle), sin(northAngle))),
                         dot(point, float2(-sin(northAngle), cos(northAngle))));
    // Wobble the mare outlines so they read as irregular basins rather than ellipses.
    float2 basin = face + 0.12f * (float2(skyNoise(face * 5 + 3), skyNoise(face * 5 + 11)) - 0.5f);
    float dark = mare(basin, float2(-0.55, -0.05), float2(0.30, 0.50)); // Oceanus Procellarum
    dark = max(dark, mare(basin, float2(-0.30, -0.45), float2(0.28, 0.22))); // Imbrium
    dark = max(dark, mare(basin, float2(0.15, -0.38), float2(0.16, 0.15))); // Serenitatis
    dark = max(dark, mare(basin, float2(0.33, -0.10), float2(0.20, 0.17))); // Tranquillitatis
    dark = max(dark, mare(basin, float2(0.68, -0.28), float2(0.11, 0.10))); // Crisium
    dark = max(dark, mare(basin, float2(0.60, 0.12), float2(0.12, 0.17))); // Fecunditatis
    dark = max(dark, mare(basin, float2(0.40, 0.27), float2(0.09, 0.09))); // Nectaris
    dark = max(dark, mare(basin, float2(-0.20, 0.35), float2(0.17, 0.14))); // Nubium
    dark = max(dark, mare(basin, float2(-0.55, 0.40), float2(0.09, 0.09))); // Humorum
    dark = max(dark, 0.8f * mare(basin, float2(0.00, -0.72), float2(0.38, 0.07))); // Frigoris
    float2 tycho = face - float2(-0.12, 0.72);
    float rays = pow(angularNoise(atan2(tycho.y, tycho.x), 18, 7), 4) * exp(-length(tycho) * 2.5f);
    float bright = exp(-dot(tycho, tycho) / 0.0012f) + 0.6f * exp(-length_squared(face - float2(-0.25, -0.15)) / 0.0009f) + 0.35f * rays;
    float grain = skyNoise(face * 9) * 0.6f + skyNoise(face * 21) * 0.4f;
    float albedo = clamp(1 - 0.36f * dark + 0.25f * bright + 0.08f * (grain - 0.5f), 0.0f, 1.2f);
    float3 surface = mix(float3(0.93, 0.92, 0.89), float3(0.72, 0.73, 0.76), dark) * albedo;

    // Lommel–Seeliger lighting keeps the full moon evenly bright, unlike Lambert.
    float2 limb = float2(sin(limbAngle), -cos(limbAngle));
    float across = dot(point, limb);
    float depth = sqrt(max(0.0f, 1 - distance * distance));
    float incidence = across * sin(phase) + depth * cos(phase);
    float lit = max(incidence, 0.0f);
    float shade = min(2 * lit / (lit + depth + 0.02f), 1.1f);
    float day = smoothstep(-0.03f, 0.06f, incidence);

    // Earthshine is strongest when the Earth looks nearly full from the Moon, i.e. thin crescents.
    float earthshine = 0.04f + 0.10f * (1 - cos(phase)) / 2;
    float3 night = float3(0.55, 0.62, 0.78) * albedo * earthshine / 0.35f;
    float3 color = mix(night * 0.35f, surface * shade, day);
    float alpha = mix(0.35f, 1.0f, day) * edge;
    return half4(half3(color * edge), half(alpha));
}
