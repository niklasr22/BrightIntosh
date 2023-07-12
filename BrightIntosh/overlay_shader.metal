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

fragment half4 fragmentShader(VertexOut in [[stage_in]]) {
    half4 overlayPixel = half4(4.25, 4.25, 4.25, 1.0); // White overlay color
    return overlayPixel;
}
