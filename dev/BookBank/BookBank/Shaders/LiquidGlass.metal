//
//  LiquidGlass.metal
//  BookBank
//
//  液体ガラス風エフェクト
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// ========================================
// リキッドグラス屈折エフェクト
// ========================================
// 背景を屈折させて色収差を出す

[[ stitchable ]] half4 liquidGlassRefraction(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float ior,           // 屈折率 (1.0〜1.3)
    float dispersion,    // 分散量 (0.01〜0.05)
    float fresnelPower   // フレネル強度 (2.0〜5.0)
) {
    // 正規化UV座標 (0〜1)
    float2 uv = position / size;
    
    // 中心を原点にしたUV (-0.5〜0.5)
    float2 centeredUV = uv - 0.5;
    
    // 円形SDF
    float radius = 0.5;
    float dist = length(centeredUV);
    
    // 円の外側は透明を返す
    if (dist > radius) {
        return half4(0.0);
    }
    
    // 中心からの方向（法線として使用）
    float2 normal2D = centeredUV / max(dist, 0.001);
    
    // エッジに近いほど屈折が強くなる
    float edgeFactor = dist / radius;
    float refractionStrength = edgeFactor * edgeFactor;
    
    // 屈折オフセット（RGB別）
    float baseOffset = (ior - 1.0) * 15.0 * refractionStrength;
    float2 offsetR = normal2D * baseOffset;
    float2 offsetG = normal2D * (baseOffset + dispersion * size.x * 0.5);
    float2 offsetB = normal2D * (baseOffset + dispersion * size.x);
    
    // サンプリング
    half4 sampleR = layer.sample(position + offsetR);
    half4 sampleG = layer.sample(position + offsetG);
    half4 sampleB = layer.sample(position + offsetB);
    
    // RGB合成（色収差）
    half3 refractedColor = half3(sampleR.r, sampleG.g, sampleB.b);
    
    // フレネル（エッジで白くなる）
    float fresnel = pow(edgeFactor, fresnelPower) * 0.5;
    refractedColor += half3(fresnel);
    
    // エッジに虹色の光を追加（色収差を視覚化）
    float rainbowStrength = edgeFactor * edgeFactor * 0.3;
    refractedColor.r += rainbowStrength;
    refractedColor.b += rainbowStrength * 0.5;
    
    return half4(refractedColor, 1.0);
}
