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


fragment float4 fragmentShader(VertexOut in [[stage_in]], constant float4 &color [[buffer(0)]]) {
    return color;
}
