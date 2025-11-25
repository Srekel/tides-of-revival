#include <stdint.h>
#define TR_API __declspec(dllexport)

extern "C"
{
TR_API int TR_initRenderer();
}
