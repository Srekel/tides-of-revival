#ifndef _MESH_SHADING_DEFINES_HLSLI_
#define _MESH_SHADING_DEFINES_HLSLI_

#define MESHLET_COUNT_MAX 1 << 20
#define CULL_INSTANCES_THREADS_COUNT 64
#define CULL_MESHLETS_THREADS_COUNT 64
#define MESHLET_THREADS_COUNT 32
#define MESHLET_MAX_TRIANGLES 124
#define MESHLET_MAX_VERTICES 64

#define COUNTER_TOTAL_CANDIDATE_MESHLETS 0
#define COUNTER_PHASE1_CANDIDATE_MESHLETS 1
#define COUNTER_PHASE2_CANDIDATE_MESHLETS 2 // TODO
#define COUNTER_PHASE1_VISIBLE_MESHLETS 0
#define COUNTER_PHASE2_VISIBLE_MESHLETS 1 // TODO

/*
	Helper functions that accelerate atomic write operations between threads using wave operations.
*/

#define InterlockedAdd_WaveOps(bufferResource, elementIndex, numValues, originalValue) 			\
{																								\
	uint count = WaveActiveCountBits(true) * numValues;											\
	if(WaveIsFirstLane())																		\
		InterlockedAdd(bufferResource[elementIndex], count, originalValue);						\
	originalValue = WaveReadLaneFirst(originalValue) + WavePrefixCountBits(true);				\
}

#define InterlockedAdd_Varying_WaveOps(bufferResource, elementIndex, numValues, originalValue) 	\
{																								\
	uint count = WaveActiveSum(numValues);														\
	if(WaveIsFirstLane())																		\
		InterlockedAdd(bufferResource[elementIndex], count, originalValue);						\
	originalValue = WaveReadLaneFirst(originalValue) + WavePrefixSum(numValues);				\
}

#define InterlockedAdd_WaveOps_ByteAddressBuffer(bufferResource, elementOffset, numValues, originalValue) 			\
{																								\
	uint count = WaveActiveCountBits(true) * numValues;											\
	if(WaveIsFirstLane())																		\
		bufferResource.InterlockedAdd(elementOffset, count, originalValue);						\
	originalValue = WaveReadLaneFirst(originalValue) + WavePrefixCountBits(true);				\
}

#define InterlockedAdd_Varying_WaveOps_ByteAddressBuffer(bufferResource, elementOffset, numValues, originalValue) 	\
{																								\
	uint count = WaveActiveSum(numValues);														\
	if(WaveIsFirstLane())																		\
		bufferResource.InterlockedAdd(elementOffset, count, originalValue);						\
	originalValue = WaveReadLaneFirst(originalValue) + WavePrefixSum(numValues);				\
}

#endif // _MESH_SHADING_DEFINES_HLSLI_