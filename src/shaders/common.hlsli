#ifndef __COMMON_HLSL__
#define __COMMON_HLSL__

#define per_object_space   space0
#define per_material_space space1
#define per_pass_space     space2
#define per_frame_space    space3

// TMP
#define MAX_LIGHTS 32
#define GAMMA 2.2

float3 gammaCorrect(float3 color) {
    float gamma = 1.0 / GAMMA;
    color = pow(color, float3(gamma, gamma, gamma));
    return color;
}

#endif