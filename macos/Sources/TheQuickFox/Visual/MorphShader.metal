#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 normalizedCoord;  // Normalized position within the quad [0, 1]
    float2 pixelCoord;       // Pixel position for border calculations
};

struct Uniforms {
    float progress;
    float2 startSize;
    float2 endSize;
    float2 startPosition;
    float2 endPosition;
};

// HSB to RGB conversion for rainbow gradient
float3 hsbToRgb(float h, float s, float b) {
    h = fract(h);
    float i = floor(h * 6.0);
    float f = h * 6.0 - i;
    float p = b * (1.0 - s);
    float q = b * (1.0 - f * s);
    float t = b * (1.0 - (1.0 - f) * s);

    int segment = int(i) % 6;
    if (segment == 0) return float3(b, t, p);
    if (segment == 1) return float3(q, b, p);
    if (segment == 2) return float3(p, b, t);
    if (segment == 3) return float3(p, q, b);
    if (segment == 4) return float3(t, p, b);
    return float3(b, p, q);
}

// Vertex shader: transforms quad vertices and passes data to fragment shader
vertex VertexOut rainbowBorderVertex(uint vertexID [[vertex_id]],
                                      constant Uniforms &uniforms [[buffer(0)]]) {
    VertexOut out;

    // Generate fullscreen quad vertices (counter-clockwise)
    // 0: bottom-left, 1: bottom-right, 2: top-left, 3: top-right
    float2 positions[4] = {
        float2(0.0, 0.0),  // bottom-left
        float2(1.0, 0.0),  // bottom-right
        float2(0.0, 1.0),  // top-left
        float2(1.0, 1.0)   // top-right
    };

    float2 normalizedPos = positions[vertexID];
    out.normalizedCoord = normalizedPos;

    // Get current window size (interpolated between start and end)
    float t = uniforms.progress;
    float smoothT = t * t * (3.0 - 2.0 * t);  // Smoothstep easing
    float2 currentSize = mix(uniforms.startSize, uniforms.endSize, smoothT);

    // Calculate pixel coordinates for border distance calculations
    out.pixelCoord = normalizedPos * currentSize;

    // Transform to NDC space [-1, 1]
    float2 ndc = normalizedPos * 2.0 - 1.0;
    ndc.y = -ndc.y;  // Flip Y for Metal's coordinate system
    out.position = float4(ndc, 0.0, 1.0);

    return out;
}

// Fragment shader: draws rainbow border with animation effects
fragment float4 rainbowBorderFragment(VertexOut in [[stage_in]],
                                       constant Uniforms &uniforms [[buffer(0)]]) {
    float t = uniforms.progress;
    float smoothT = t * t * (3.0 - 2.0 * t);

    // Get current window size
    float2 currentSize = mix(uniforms.startSize, uniforms.endSize, smoothT);

    // Calculate distance from edges (in pixels)
    float borderWidthPixels = 4.0;
    float distFromLeft = in.pixelCoord.x;
    float distFromRight = currentSize.x - in.pixelCoord.x;
    float distFromTop = in.pixelCoord.y;
    float distFromBottom = currentSize.y - in.pixelCoord.y;
    float minDistPixels = min(min(distFromLeft, distFromRight), min(distFromTop, distFromBottom));

    // Discard pixels outside border region (early fragment discard for performance)
    if (minDistPixels > borderWidthPixels) {
        discard_fragment();
    }

    // Generate rainbow gradient based on position
    float gradientPos = (in.normalizedCoord.x + in.normalizedCoord.y) * 0.5;
    gradientPos += t * 0.3;  // Animate gradient flow
    float3 rgb = hsbToRgb(gradientPos, 0.95, 0.95);

    // Apply warping effect during animation
    float2 center = float2(0.5, 0.5);
    float2 fromCenter = in.normalizedCoord - center;
    float distFromCenter = length(fromCenter);

    // Edge glow that pulses during animation
    float edgeGlow = 1.0 + 0.5 * sin(smoothT * M_PI_F * 3.0);
    rgb *= edgeGlow;

    // Alpha based on distance from edge for smooth anti-aliased borders
    float borderFade = smoothstep(0.0, borderWidthPixels, minDistPixels);
    float alpha = 0.9 * (1.0 - borderFade);

    // Trail effect - fade as animation progresses
    float trailFade = mix(1.0, 0.7, smoothT);
    alpha *= trailFade;

    return float4(rgb, alpha);
}
