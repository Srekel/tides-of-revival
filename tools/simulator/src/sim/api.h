#pragma once

#ifdef __cplusplus
extern "C"
{
#endif

#define CALLCONV

    typedef void(CALLCONV *PFN_simulate)();

    struct SimulatorAPI
    {
        PFN_simulate simulate;
    };

#ifdef __cplusplus
}
#endif
