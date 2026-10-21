#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 todaySky(float2 position, float elevation, float rising, float horizonY) {
    float height = max(horizonY - position.y, 0.0f);
    float horizon = exp(-height / 100.0f);
    float day = smoothstep(-8.0f, 8.0f, elevation);
    float twilight = smoothstep(-18.0f, -5.0f, elevation) * (1 - smoothstep(2.0f, 14.0f, elevation));
    float3 night = mix(float3(0.009, 0.018, 0.055), float3(0.055, 0.075, 0.14), horizon);
    float3 daylight = mix(float3(0.085, 0.32, 0.64), float3(0.65, 0.81, 0.88), horizon);
    float3 color = mix(night, daylight, day);
    float3 warm = mix(float3(0.96, 0.32, 0.12), float3(0.87, 0.46, 0.45), rising);
    color = mix(color, warm, twilight * horizon * 0.8f);
    // Static decorative stars: no sensor updates or perpetual animation.
    float2 starsUV = position / 5.0f;
    float seed = fract(sin(dot(floor(starsUV), float2(127.1, 311.7))) * 43758.5453f);
    float star = (1 - smoothstep(0.02f, 0.16f, length(fract(starsUV) - 0.5f))) * step(0.985f, seed);
    color += star * (1 - smoothstep(-18.0f, -8.0f, elevation)) * smoothstep(0.0f, 70.0f, height) * 0.65f;
    float3 belowHorizon = mix(float3(0.008, 0.014, 0.025), float3(0.10, 0.16, 0.20), day);
    color = mix(color, belowHorizon, smoothstep(horizonY, horizonY + 90, position.y));
    return half4(half3(color), 1);
}
