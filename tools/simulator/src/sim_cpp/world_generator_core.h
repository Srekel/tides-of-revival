#include "world_generator.h"

#ifdef __cplusplus
extern "C"
{
#endif

    __declspec(dllexport) void generate_landscape_from_image(struct Voronoi *grid, const char *image_path);

    // NOTE: Utility function, not a mutator
    __declspec(dllexport) unsigned char *generate_landscape_preview(struct Voronoi *grid, unsigned int image_width, unsigned int image_height);
    __declspec(dllexport) float *voronoi_to_imagef32(struct Voronoi *grid, unsigned int image_width, unsigned int image_height);

#ifdef __cplusplus
}
#endif