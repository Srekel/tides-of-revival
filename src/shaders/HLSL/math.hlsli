#ifndef _MATH_HLSLI_
#define _MATH_HLSLI_

#define MATH_PI 3.141592653589f
#define MATH_TAU MATH_PI * 2.0f

float3 RotateAboutAxis(float3 vector, float3 axis, float rotation)
{
    float s = sin(rotation);
    float c = cos(rotation);
    float oneMinusC = 1.0 - c;

    axis = normalize(axis);
    float3x3 rotationMatrix =
        {oneMinusC * axis.x * axis.x + c, oneMinusC * axis.x * axis.y - axis.z * s, oneMinusC * axis.z * axis.x + axis.y * s,
         oneMinusC * axis.x * axis.y + axis.z * s, oneMinusC * axis.y * axis.y + c, oneMinusC * axis.y * axis.z - axis.x * s,
         oneMinusC * axis.z * axis.x - axis.y * s, oneMinusC * axis.y * axis.z + axis.x * s, oneMinusC * axis.z * axis.z + c};

    return mul(rotationMatrix, vector);
}

void ClipSpaceAabbMinMax(float3 aabb_center, float3 aabb_extents, float4x4 world, float4x4 view_proj, out float3 rect_min, out float3 rect_max)
{
    float3 ext = aabb_extents * 2.0f;
    float4x4 extents_basis = float4x4(
        ext.x, 0.0, 0.0, 0.0,
        0.0, ext.y, 0.0, 0.0,
        0.0, 0.0, ext.z, 0.0,
        0.0, 0.0, 0.0, 0.0);
    float4x4 axis = mul(mul(extents_basis, world), view_proj);

    float4 corner_000 = mul(mul(float4(aabb_center - aabb_extents, 1), world), view_proj);
    float4 corner_100 = corner_000 + axis[0];
    float4 corner_010 = corner_000 + axis[1];
    float4 corner_110 = corner_010 + axis[0];
    float4 corner_001 = corner_000 + axis[2];
    float4 corner_101 = corner_100 + axis[2];
    float4 corner_011 = corner_010 + axis[2];
    float4 corner_111 = corner_110 + axis[2];

    // Clip-space AABB
    float3 corner_000_cs = corner_000.xyz / corner_000.w;
    float3 corner_100_cs = corner_100.xyz / corner_100.w;
    float3 corner_010_cs = corner_010.xyz / corner_010.w;
    float3 corner_110_cs = corner_110.xyz / corner_110.w;
    float3 corner_001_cs = corner_001.xyz / corner_001.w;
    float3 corner_101_cs = corner_101.xyz / corner_101.w;
    float3 corner_011_cs = corner_011.xyz / corner_011.w;
    float3 corner_111_cs = corner_111.xyz / corner_111.w;

    rect_min = min(corner_000_cs, corner_100_cs);
    rect_min = min(rect_min, corner_010_cs);
    rect_min = min(rect_min, corner_110_cs);
    rect_min = min(rect_min, corner_001_cs);
    rect_min = min(rect_min, corner_101_cs);
    rect_min = min(rect_min, corner_011_cs);
    rect_min = min(rect_min, corner_111_cs);
    rect_min = min(rect_min, float3(1, 1, 1));

    rect_max = max(corner_000_cs, corner_100_cs);
    rect_max = max(rect_max, corner_010_cs);
    rect_max = max(rect_max, corner_110_cs);
    rect_max = max(rect_max, corner_001_cs);
    rect_max = max(rect_max, corner_101_cs);
    rect_max = max(rect_max, corner_011_cs);
    rect_max = max(rect_max, corner_111_cs);
    rect_max = max(rect_max, float3(-1, -1, -1));
}

float CalculateScreenPercentage(float3 aabb_center, float3 aabb_extents, float4x4 world, float4x4 view_proj)
{
    return 0.1f;
}

bool FrustumCull(float3 aabb_center, float3 aabb_extents, float4x4 world, float4x4 view_proj)
{
    bool is_visible = true;

    float3 ext = aabb_extents * 2.0f;
    float4x4 extents_basis = float4x4(
        ext.x, 0.0, 0.0, 0.0,
        0.0, ext.y, 0.0, 0.0,
        0.0, 0.0, ext.z, 0.0,
        0.0, 0.0, 0.0, 0.0);
    float4x4 axis = mul(mul(extents_basis, world), view_proj);

    float4 corner_000 = mul(mul(float4(aabb_center - aabb_extents, 1), world), view_proj);
    float4 corner_100 = corner_000 + axis[0];
    float4 corner_010 = corner_000 + axis[1];
    float4 corner_110 = corner_010 + axis[0];
    float4 corner_001 = corner_000 + axis[2];
    float4 corner_101 = corner_100 + axis[2];
    float4 corner_011 = corner_010 + axis[2];
    float4 corner_111 = corner_110 + axis[2];

    float min_w = min(corner_000.w, corner_001.w);
    min_w = min(min_w, corner_010.w);
    min_w = min(min_w, corner_011.w);
    min_w = min(min_w, corner_100.w);
    min_w = min(min_w, corner_101.w);
    min_w = min(min_w, corner_110.w);
    min_w = min(min_w, corner_111.w);

    float max_w = max(corner_000.w, corner_001.w);
    max_w = max(max_w, corner_010.w);
    max_w = max(max_w, corner_011.w);
    max_w = max(max_w, corner_100.w);
    max_w = max(max_w, corner_101.w);
    max_w = max(max_w, corner_110.w);
    max_w = max(max_w, corner_111.w);

    // Plane inequalities
    float4 plane_mins = min(float4(corner_000.xy, -corner_000.xy) - corner_000.w, float4(corner_001.xy, -corner_001.xy) - corner_001.w);
    plane_mins = min(plane_mins, float4(corner_010.xy, -corner_010.xy) - corner_010.w);
    plane_mins = min(plane_mins, float4(corner_100.xy, -corner_100.xy) - corner_100.w);
    plane_mins = min(plane_mins, float4(corner_110.xy, -corner_110.xy) - corner_110.w);
    plane_mins = min(plane_mins, float4(corner_011.xy, -corner_011.xy) - corner_011.w);
    plane_mins = min(plane_mins, float4(corner_101.xy, -corner_101.xy) - corner_101.w);
    plane_mins = min(plane_mins, float4(corner_111.xy, -corner_111.xy) - corner_111.w);
    plane_mins = min(plane_mins, float4(1, 1, 1, 1));

    // Clip-space AABB
    float3 corner_000_cs = corner_000.xyz / corner_000.w;
    float3 corner_100_cs = corner_100.xyz / corner_100.w;
    float3 corner_010_cs = corner_010.xyz / corner_010.w;
    float3 corner_110_cs = corner_110.xyz / corner_110.w;
    float3 corner_001_cs = corner_001.xyz / corner_001.w;
    float3 corner_101_cs = corner_101.xyz / corner_101.w;
    float3 corner_011_cs = corner_011.xyz / corner_011.w;
    float3 corner_111_cs = corner_111.xyz / corner_111.w;

    float3 rect_min = min(corner_000_cs, corner_100_cs);
    rect_min = min(rect_min, corner_010_cs);
    rect_min = min(rect_min, corner_110_cs);
    rect_min = min(rect_min, corner_001_cs);
    rect_min = min(rect_min, corner_101_cs);
    rect_min = min(rect_min, corner_011_cs);
    rect_min = min(rect_min, corner_111_cs);
    rect_min = min(rect_min, float3(1, 1, 1));

    float3 rect_max = max(corner_000_cs, corner_100_cs);
    rect_max = max(rect_max, corner_010_cs);
    rect_max = max(rect_max, corner_110_cs);
    rect_max = max(rect_max, corner_001_cs);
    rect_max = max(rect_max, corner_101_cs);
    rect_max = max(rect_max, corner_011_cs);
    rect_max = max(rect_max, corner_111_cs);
    rect_max = max(rect_max, float3(-1, -1, -1));

    is_visible &= rect_max.z > 0;

    if (min_w <= 0 && max_w > 0)
    {
        rect_min = -1;
        rect_max = 1;
        is_visible = true;
    }
    else
    {
        is_visible &= max_w > 0.0f;
    }

    is_visible &= !any(plane_mins > 0.0f);

    return is_visible;
}

// From "NEXT GENERATION POST PROCESSING IN CALL OF DUTY: ADVANCED WARFARE"
// http://advances.realtimerendering.com/s2014/index.html
float InterleavedGradientNoise(float2 uv)
{
    const float3 magic = float3(0.06711056f, 0.00583715f, 52.9829189f);
    return frac(magic.z * frac(dot(uv, magic.xy)));
}
float InterleavedGradientNoise(float2 uv, float offset)
{
    uv += offset * (float2(47, 17) * 0.695f);
    const float3 magic = float3(0.06711056f, 0.00583715f, 52.9829189f);
    return frac(magic.z * frac(dot(uv, magic.xy)));
}

#endif // _MATH_HLSLI_