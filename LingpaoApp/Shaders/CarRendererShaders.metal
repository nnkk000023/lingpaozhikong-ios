#include <metal_stdlib>
using namespace metal;

/// GPU 实时金属车漆着染 Compute Kernel（严格对应 `C2210sg0.i/j` Rec.709 分段高光保留公式）
kernel void metallicPaintTint(
    texture2d<float, access::read> srcTex [[texture(0)]],
    texture2d<float, access::read> maskTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant float3 &targetRGB [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }

    float4 src = srcTex.read(gid);
    if (src.a <= 0.001f) {
        outTex.write(src, gid);
        return;
    }

    float mask = maskTex.read(gid).b;
    if (mask <= 0.001f) {
        outTex.write(src, gid);
        return;
    }

    // Rec.709 相对亮度与分段高光调制
    float lum = 0.2126f * src.r + 0.7152f * src.g + 0.0722f * src.b;
    float fN = min(lum / 0.65f, 1.0f);
    float fQ = clamp((lum - 0.65f) / 0.35f, 0.0f, 1.0f);
    float f3 = fQ * fQ * 0.65f;

    float3 base = targetRGB * fN;
    float3 shaded = ((1.0f - base) * f3) + base;
    float3 finalRGB = clamp(mix(src.rgb, shaded, mask), 0.0f, 1.0f);

    outTex.write(float4(finalRGB, src.a), gid);
}

/// SwiftUI `colorEffect`：充电专页竖向 SOC 电量渐变流光呼吸着染
[[stitchable]] half4 chargePulseEffect(
    float2 position,
    half4 color,
    float height,
    float progress,
    float time
) {
    if (color.a <= 0.001h) {
        return color;
    }
    float normalizedY = 1.0f - clamp(position.y / max(height, 1.0f), 0.0f, 1.0f);
    if (normalizedY > progress) {
        return half4(0.35h, 0.39h, 0.45h, color.a * 0.22h);
    }
    // 由下向上的能量流光波
    float wave = 0.5f + 0.5f * sin(normalizedY * 14.0f - time * 3.4f);
    half3 baseGreen = mix(half3(0.10h, 0.62h, 0.38h), half3(0.28h, 0.88h, 0.56h), half(normalizedY));
    half3 glow = baseGreen + half3(0.10h, 0.16h, 0.10h) * half(wave);
    return half4(glow * color.a, color.a);
}

/// SwiftUI `colorEffect`：座椅热区微光呼吸脉动（加热暖橙 / 通风冰蓝）
[[stitchable]] half4 seatThermalGlow(
    float2 position,
    half4 color,
    float isHeating,
    float intensity,
    float time
) {
    if (color.a <= 0.001h || intensity <= 0.01f) {
        return color;
    }
    float pulse = 0.90f + 0.10f * sin(time * 2.6f);
    half3 tint = isHeating > 0.5f ? half3(0.95h, 0.48h, 0.22h) : half3(0.22h, 0.56h, 0.96h);
    half3 blended = mix(color.rgb, tint * color.a, half(clamp(intensity * 0.35f * pulse, 0.0f, 0.6f)));
    return half4(blended, color.a);
}

/// SwiftUI `colorEffect`：座舱空调流体气流与冷暖风场波纹（mode: 0制冷/1极速降温/2升温与制热/3除味/4除霜）
[[stitchable]] half4 cabinAirflowEffect(
    float2 position,
    half4 color,
    float height,
    float mode,
    float time
) {
    if (color.a <= 0.002h) {
        return color;
    }

    float normY = clamp(position.y / max(height, 1.0f), 0.0f, 1.0f);
    float speed = (mode == 1.0f || mode == 2.0f) ? 4.4f : 2.6f;
    float freq = (mode == 1.0f || mode == 2.0f) ? 20.0f : 14.0f;

    // 气流自前风挡/中控出风口向后排推进的脉冲波纹
    float primaryWave = 0.55f + 0.45f * sin(normY * freq - time * speed);
    float secondaryWave = 0.50f + 0.50f * cos(position.x * 0.08f + normY * 10.0f - time * (speed * 0.7f));
    float intensity = clamp(primaryWave * 0.70f + secondaryWave * 0.30f, 0.20f, 1.0f);

    half3 tint;
    half strength;
    if (mode > 3.5f) {
        // 4: 前挡除霜（暖白金脉冲）
        tint = half3(1.00h, 0.84h, 0.52h);
        strength = half(intensity * 0.82f);
    } else if (mode > 2.5f) {
        // 3: 快速除味（清透翠绿）
        tint = half3(0.22h, 0.85h, 0.58h);
        strength = half(intensity * 0.74f);
    } else if (mode > 1.5f) {
        // 2: 制热 / 极速升温（暖琥珀橙红热流）
        tint = half3(0.98h, 0.46h, 0.20h);
        strength = half(intensity * 0.90f);
    } else if (mode > 0.5f) {
        // 1: 极速降温（高饱和冰青强风波）
        tint = half3(0.18h, 0.78h, 1.00h);
        strength = half(intensity * 0.92f);
    } else {
        // 0: 常规制冷（冰蓝柔风）
        tint = half3(0.32h, 0.65h, 0.98h);
        strength = half(intensity * 0.75f);
    }

    half outAlpha = clamp(color.a * strength, 0.0h, 0.92h);
    return half4(tint * outAlpha, outAlpha);
}
