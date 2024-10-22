#pragma once

#ifdef __cplusplus
extern "C"
{
#endif

#define DLLEXPORT __declspec(dllexport)
#define CALLCONV

    struct SimulatorAPI;
    struct ComputeInfo;
    DLLEXPORT void runUI(const struct SimulatorAPI *api);
    DLLEXPORT void compute(const struct ComputeInfo *info);

    typedef void(CALLCONV *PFN_runUI)(const struct SimulatorAPI *api);
    typedef void(CALLCONV *PFN_compute)(const struct ComputeInfo *info);

#ifdef __cplusplus
}
#endif
