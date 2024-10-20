cbuffer RemapData : register(b0)
{
    float2 from;
    float2 to;
    uint buffer_width;
    uint buffer_height;
    float2 _padding;
}

StructuredBuffer<float> InputBuffer : register(t0);
RWStructuredBuffer<float> OutputBuffer : register(u0);

float Remap(float Value, float2 from, float2 to)
{
    return to.x + (Value - from.x) * (to.y - to.x) / (from.y - from.x);
}

[numthreads(8, 8, 1)]
void CSRemap(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x < buffer_width && DTid.y < buffer_height)
    {
        uint index = DTid.x + DTid.y * buffer_width;
        OutputBuffer[index] = Remap(InputBuffer[index], from, to);
    }
}