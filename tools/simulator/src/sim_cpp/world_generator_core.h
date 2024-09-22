#include "world_generator.h"

#ifdef __cplusplus
extern "C"
{
#endif

    __declspec(dllexport) void generate_voronoi_map(map_settings_t settings, grid_t *grid);
    __declspec(dllexport) void generate_landscape_from_image(map_settings_t settings, grid_t *grid, const char *image_path);
    __declspec(dllexport) void generate_landscape(map_settings_t settings, grid_t *grid);

    // NOTE: Utility function, not a mutator
    __declspec(dllexport) unsigned char *generate_landscape_preview(grid_t *grid, unsigned int image_width, unsigned int image_height);

#ifdef __cplusplus
}
#endif