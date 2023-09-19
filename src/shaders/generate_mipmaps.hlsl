#define root_signature \
    "RootConstants(b0, num32BitConstants = 2), " \
    "DescriptorTable(SRV(t0), UAV(u0, numDescriptors = 4))"

Texture2D<float4> srv_src_mipmap : register(t0);
RWTexture2D<float4> uav_mipmap1 : register(u0);
RWTexture2D<float4> uav_mipmap2 : register(u1);
RWTexture2D<float4> uav_mipmap3 : register(u2);
RWTexture2D<float4> uav_mipmap4 : register(u3);

struct Const {
    uint src_mip_level;
    uint num_mip_levels;
};
ConstantBuffer<Const> cbv_const : register(b0);

groupshared float gs_red[64];
groupshared float gs_green[64];
groupshared float gs_blue[64];
groupshared float gs_alpha[64];

void storeColor(uint idx, float4 color) {
    gs_red[idx] = color.r;
    gs_green[idx] = color.g;
    gs_blue[idx] = color.b;
    gs_alpha[idx] = color.a;
}

float4 loadColor(uint idx) {
    return float4(gs_red[idx], gs_green[idx], gs_blue[idx], gs_alpha[idx]);
}

[RootSignature(root_signature)]
[numthreads(8, 8, 1)]
void csGenerateMipmaps(
    uint3 dispatch_id : SV_DispatchThreadID,
    uint group_idx : SV_GroupIndex
) {
    const uint x = dispatch_id.x * 2;
    const uint y = dispatch_id.y * 2;

    float4 s00 = srv_src_mipmap.mips[cbv_const.src_mip_level][uint2(x, y)];
    float4 s10 = srv_src_mipmap.mips[cbv_const.src_mip_level][uint2(x + 1, y)];
    float4 s01 = srv_src_mipmap.mips[cbv_const.src_mip_level][uint2(x, y + 1)];
    float4 s11 = srv_src_mipmap.mips[cbv_const.src_mip_level][uint2(x + 1, y + 1)];
    s00 = 0.25f * (s00 + s01 + s10 + s11);

    uav_mipmap1[dispatch_id.xy] = s00;
    storeColor(group_idx, s00);
    if (cbv_const.num_mip_levels == 1) {
        return;
    }
    GroupMemoryBarrierWithGroupSync();

    if ((group_idx & 0x9) == 0) {
        s10 = loadColor(group_idx + 1);
        s01 = loadColor(group_idx + 8);
        s11 = loadColor(group_idx + 9);
        s00 = 0.25f * (s00 + s01 + s10 + s11);
        uav_mipmap2[dispatch_id.xy / 2] = s00;
        storeColor(group_idx, s00);
    }
    if (cbv_const.num_mip_levels == 2) {
        return;
    }
    GroupMemoryBarrierWithGroupSync();

    if ((group_idx & 0x1B) == 0) {
        s10 = loadColor(group_idx + 2);
        s01 = loadColor(group_idx + 16);
        s11 = loadColor(group_idx + 18);
        s00 = 0.25f * (s00 + s01 + s10 + s11);
        uav_mipmap3[dispatch_id.xy / 4] = s00;
        storeColor(group_idx, s00);
    }
    if (cbv_const.num_mip_levels == 3) {
        return;
    }
    GroupMemoryBarrierWithGroupSync();

    if (group_idx == 0) {
        s10 = loadColor(group_idx + 4);
        s01 = loadColor(group_idx + 32);
        s11 = loadColor(group_idx + 36);
        s00 = 0.25f * (s00 + s01 + s10 + s11);
        uav_mipmap4[dispatch_id.xy / 8] = s00;
        storeColor(group_idx, s00);
    }
}