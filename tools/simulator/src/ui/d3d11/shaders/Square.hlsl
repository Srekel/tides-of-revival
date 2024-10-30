cbuffer SquareData : register(b0)
{
    uint buffer_width;
    uint buffer_height;
    float2 _padding;
}

StructuredBuffer<float> InputBuffer : register(t0);
RWStructuredBuffer<float> OutputBuffer : register(u0);

[numthreads(8, 8, 1)]
void CSSquare(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x < buffer_width && DTid.y < buffer_height)
    {
        uint index = DTid.x + DTid.y * buffer_width;
        float value = InputBuffer[index];
        OutputBuffer[index] = value * value;
    }
}