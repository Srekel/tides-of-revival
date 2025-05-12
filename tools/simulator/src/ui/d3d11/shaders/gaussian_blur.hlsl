// Adapted from Gigi Gaussian Blur sample
// ======================================

// Calculations adapted from http://demofox.org/gauss.html

cbuffer constant_buffer_0 : register(b0)
{
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float g_sigma;
    float g_support;
};

StructuredBuffer<float> g_input : register(t0);
RWStructuredBuffer<float> g_output : register(u0);

// #define c_sigma /*$(Variable:Sigma)*/
// #define c_support /*$(Variable:Support)*/

float erf(float x)
{
    // save the sign of x
    float sign = (x >= 0) ? 1 : -1;
    x = abs(x);

    // constants
    static const float a1 = 0.254829592;
    static const float a2 = -0.284496736;
    static const float a3 = 1.421413741;
    static const float a4 = -1.453152027;
    static const float a5 = 1.061405429;
    static const float p = 0.3275911;

    // A&S formula 7.1.26
    float t = 1.0 / (1.0 + p * x);
    float y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-x * x);
    return sign * y; // erf(-x) = -erf(x);
}

float IntegrateGaussian(float x, float sigma)
{
    float p1 = erf((x - 0.5) / sigma * sqrt(0.5));
    float p2 = erf((x + 0.5) / sigma * sqrt(0.5));
    return (p2 - p1) / 2.0;
}

[numthreads(32, 32, 1)] void CSGaussianBlur(uint3 DTid : SV_DispatchThreadID)
{
    int2 px = DTid.xy;
    int2 maxPx = int2(g_in_buffer_width, g_in_buffer_height);
    maxPx -= int2(1, 1);

    // calculate radius of our blur based on sigma and support percentage
    const int radius = int(ceil(sqrt(-2.0 * g_sigma * g_sigma * log(1.0 - g_support))));

    // initialize values
    float weight = 0.0f;
    float output = 0.0f;

    // loop horizontally or vertically, as appropriate
    for (int index = -radius; index <= radius; ++index)
    {
        float kernel = IntegrateGaussian(index, g_sigma);

#ifdef BLUR_HORIZONTAL
        int2 offset = int2(index, 0);
#else
        int2 offset = int2(0, index);
#endif

        int2 readPx = clamp(px + offset, int2(0, 0), maxPx);

        output += g_input[readPx.x + readPx.y * g_in_buffer_width] * kernel;
        weight += kernel;
    }

    // normalize blur
    output /= weight;

    g_output[px.x + px.y * g_in_buffer_width] = output;
}

/*
Shader Resources:
    Texture Input (as SRV)
    Texture Output (as UAV)
*/
