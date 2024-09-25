#pragma once

#ifdef __cplusplus
extern "C"
{
#endif

#define CALLCONV

    typedef void(CALLCONV *PFN_simulate)();
    typedef void(CALLCONV *PFN_simulateSteps)(unsigned int steps);
    typedef unsigned char *(CALLCONV *PFN_get_preview)(unsigned int image_width, unsigned int image_height);

    struct SimulatorAPI
    {
        PFN_simulate simulate;
        PFN_simulateSteps simulateSteps;
        PFN_get_preview get_preview;
    };

#ifdef __cplusplus
}
#endif
