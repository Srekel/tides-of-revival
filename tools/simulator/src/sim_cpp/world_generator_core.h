#include "world_generator.h"

#ifdef __cplusplus
extern "C"
{
#endif

    __declspec(dllexport) void generate_voronoi_map(const struct MapSettings *map_settings, const struct VoronoiSettings *voronoi_settings, struct Grid *grid);
    __declspec(dllexport) void generate_landscape_from_image(struct Grid *grid, const char *image_path);
    __declspec(dllexport) void generate_landscape(const struct MapSettings *settings, struct Grid *grid);

    // NOTE: Utility function, not a mutator
    __declspec(dllexport) unsigned char *generate_landscape_preview(struct Grid *grid, unsigned int image_width, unsigned int image_height);

#ifdef __cplusplus
}
#endif