#pragma once

#ifdef __cplusplus
extern "C"
{
#endif

#define CALLCONV

    struct SimulatorProgress
    {
        float percent;
    };

    typedef void(CALLCONV *PFN_simulate)(void);
    typedef void(CALLCONV *PFN_simulateSteps)(unsigned int steps);
    typedef unsigned char *(CALLCONV *PFN_get_preview)(unsigned int image_width, unsigned int image_height);
    typedef struct SimulatorProgress(CALLCONV *PFN_getProgress)(void);

    struct SimulatorAPI
    {
        PFN_simulate simulate;
        PFN_simulateSteps simulateSteps;
        PFN_get_preview get_preview;
        PFN_getProgress getProgress;
    };

#ifdef __cplusplus
}
#endif
