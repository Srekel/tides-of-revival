#define DIRECT3D12
#define STAGE_VERT

#include "ui_resources.hlsl"

VSOutput VS_MAIN(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID)
{
    INIT_MAIN;
    VSOutput Out;
    Out.InstanceID = instanceID;

    uint2 quadVertexPosition = quadVertexPositions[vertexID];

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[Get(uiTransformBufferIndex)];
    UITransform instance = instanceTransformBuffer.Load<UITransform>(instanceID * sizeof(UITransform));

    float2 position = float2(instance.rect[quadVertexPosition.x], instance.rect[quadVertexPosition.y]);

    Out.Position = mul(Get(screenToClip), float4(position, 0.0f, 1.0f));
    Out.UV = quadVertexUVs[vertexID];

    RETURN(Out);
}
