#pragma once

#ifdef __cplusplus
extern "C"
{
#endif

#define DLLEXPORT __declspec(dllexport)
#define CALLCONV

    struct SimulatorAPI;
    DLLEXPORT void runUI(const struct SimulatorAPI *api);

    typedef void(CALLCONV *PFN_runUI)(const struct SimulatorAPI *api);

#ifdef __cplusplus
}
#endif
