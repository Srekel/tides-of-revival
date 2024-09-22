#ifdef __cplusplus
extern "C"
{
#endif

#define DLLEXPORT __declspec(dllexport)
#define CALLCONV

    DLLEXPORT void runUI();

    typedef void(CALLCONV *PFN_runUI)();

#ifdef __cplusplus
}
#endif
