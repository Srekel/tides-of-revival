
cbuffer constant_buffer_0 : register(b0)
{
    // out buffer is always 2x
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float2 _padding;
};

// bool use_input = false;
// unsigned buffer_width_index = 0;

StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);

[numthreads(32, 32, 1)]
void CSDownsample(uint3 DTid : SV_DispatchThreadID) {
    uint out_buffer_width = g_in_buffer_width / 2;
    uint input_index = (DTid.x) + (DTid.y) * g_in_buffer_width;
    uint output_index = floor(DTid.x / 2) + floor(DTid.y / 2) * out_buffer_width;
    float3 color = g_input_buffer[input_index];
    g_output_buffer[output_index] = color * 0.25;
}
