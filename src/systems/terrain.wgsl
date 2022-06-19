// This type definition is just to make typing a bit easier
type float4 = vec4<f32>;

struct VertexInput {
    [[location(0)]] position: float2;
    [[location(1)]] height: float;
};

struct VertexOutput {
    // This is the equivalent of gl_Position in GLSL
    [[builtin(position)]] position: float4;
    [[location(0)]] color: float4;
};

[[stage(vertex)]]
fn vertex_main(vert: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.color = float4(vert.position.x * 0.01,0.5,1,1);
    out.position = float4(vert.position.x, 0vert.position.z, 0);
    return out;
};

[[stage(fragment)]]
fn fragment_main(in: VertexOutput) -> [[location(0)]] float4 {
    return float4(in.color);
}