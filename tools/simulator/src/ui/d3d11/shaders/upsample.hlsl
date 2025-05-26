
#define COMPUTE_OPERATOR_NEAREST 4
#define COMPUTE_OPERATOR_FIRST 5

cbuffer constant_buffer_0 : register(b0)
{
    // out buffer is always 2x
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    uint g_operator;
    uint g_radius; // in out-buffer space (TODO)
};

StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);

[numthreads(32, 32, 1)]
void CSUpsample(uint3 DTid : SV_DispatchThreadID) {
    uint out_buffer_width = g_in_buffer_width * 2;
    uint input_index = (DTid.x) + (DTid.y) * g_in_buffer_width;
    if (g_operator == COMPUTE_OPERATOR_NEAREST) {
        float color = g_input_buffer[input_index];
        for (uint y = 0; y < 2; y++) {
            for (uint x = 0; x < 2; x++) {
                uint output_index = (DTid.x * 2 + x) + (DTid.y * 2 + y) * out_buffer_width;
                g_output_buffer[output_index] = color;
            }
        }
    }
    else if (g_operator == COMPUTE_OPERATOR_FIRST) {
        for (uint y = 0; y < 2; y++) {
            for (uint x = 0; x < 2; x++) {
                uint output_index = (DTid.x * 2 + x) + (DTid.y * 2 + y) * out_buffer_width;
                g_output_buffer[output_index] = 0;
            }
        }

        float color = g_input_buffer[input_index];
        uint output_index = (DTid.x * 2) + (DTid.y * 2) * out_buffer_width;
        g_output_buffer[output_index] = color;
    }
}
