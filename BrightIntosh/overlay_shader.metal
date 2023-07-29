#include <metal_stdlib>

using namespace metal;

struct VertexIn {
    float4 position [[position]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(constant VertexIn* vertexArray [[buffer(0)]], uint vertexId [[vertex_id]]) {
    VertexOut out;
    out.position = vertexArray[vertexId].position;
    return out;
}


fragment float4 fragmentShader(VertexOut in [[stage_in]], constant float4 &color [[buffer(1)]]) {
    //half4 overlayPixel = half4(4.25, 4.25, 4.25, 1.0); // White overlay color
    // overlayPixel = half4(half(color[0]), half(color[1]), half(color[1]), half(color[1]));
    return color;
}
