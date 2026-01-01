
#define COMPUTE_OPERATOR_AVERAGE 3
#define COMPUTE_OPERATOR_NEAREST 4
#define COMPUTE_OPERATOR_FIRST 5

cbuffer constant_buffer_0 : register(b0) {
    // out buffer is always 2x
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    uint g_operator;
    uint g_radius; // in out-buffer space (TODO)
};

StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);

// 
//             |         |         |
//          --ITL--------┼--------ITR--
//             |         |         |
//             |   200   |   100   |
//             |         |         |
//          --OTL-------OTR--------┼---
//             |         |         |
//             |   100   |   150   |
//             |         |         |
//          --[BL]------OBR-------IBR--
//             |         |         |
// 
//                  4x4 --> 8x8
// 
//    BL          BL     BR     TL     TR
//   (0,0) -> [  (0,0)  (1,0)  (0,1)  (1,1)  ]
//   (1,1) -> [  (2,2)  (3,2)  (2,3)  (3,3)  ]
// 
//    BL       IBL       OBL    OBR    OTL    OTR
//   (0,0) ->   0   ->    0      1      8      9         (bottom left corner)
//   (3,0) ->   3   ->    6      7      14     15        (bottom right corner)
//   (0,1) ->   4   ->    16     17     24     25        (one row up, left)
// 

[numthreads(32, 32, 1)]
void CSUpsample(uint3 DTid : SV_DispatchThreadID) {
    uint out_buffer_width = g_in_buffer_width * 2;
    uint input_index = (DTid.x) + (DTid.y) * g_in_buffer_width;
    if (g_operator == COMPUTE_OPERATOR_AVERAGE) {
        if (DTid.x + 2 < g_in_buffer_width && DTid.y + 2 < g_in_buffer_height) {
            uint index_IBL = DTid.x + 0 + (DTid.y + 0) * g_in_buffer_width;
            uint index_IBR = DTid.x + 1 + (DTid.y + 0) * g_in_buffer_width;
            uint index_ITL = DTid.x + 0 + (DTid.y + 1) * g_in_buffer_width;
            uint index_ITR = DTid.x + 1 + (DTid.y + 1) * g_in_buffer_width;

            uint index_OBL = 2 * DTid.x + 0 + (2 * DTid.y + 0) * out_buffer_width;
            uint index_OBR = 2 * DTid.x + 1 + (2 * DTid.y + 0) * out_buffer_width;
            uint index_OTL = 2 * DTid.x + 0 + (2 * DTid.y + 1) * out_buffer_width;
            uint index_OTR = 2 * DTid.x + 1 + (2 * DTid.y + 1) * out_buffer_width;

            float color_OBL = g_input_buffer[index_IBL];
            float color_OBR = lerp(color_OBL, g_input_buffer[index_IBR], 0.5);
            float color_OTL = lerp(color_OBL, g_input_buffer[index_ITL], 0.5);
            float color_OTR = lerp(color_OBL, g_input_buffer[index_ITR], 0.5);

            g_output_buffer[index_OBL] = color_OBL;
            g_output_buffer[index_OBR] = color_OBR;
            g_output_buffer[index_OTL] = color_OTL;
            g_output_buffer[index_OTR] = color_OTR;
        }
        else {
            float color = g_input_buffer[input_index];
            uint output_index = (DTid.x * 2) + (DTid.y * 2) * out_buffer_width;
            g_output_buffer[output_index] = color;
        }
    }
    else if (g_operator == COMPUTE_OPERATOR_NEAREST) {
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
    else {
        uint output_index = (DTid.x * 2) + (DTid.y * 2) * out_buffer_width;
        g_output_buffer[output_index] = DTid.x % 2; // not implemented
    }
}
