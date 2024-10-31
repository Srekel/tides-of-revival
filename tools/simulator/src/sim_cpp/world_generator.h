#pragma once

#if defined(_WIN32)
#define CPP_NODES_API __stdcall
#elif
#error Unsupported OS
#endif

enum VoronoiCellType
{
	NONE = 0,
	WATER = 1,
	LAND = 2,
	SHORE = 3,
	MOUNTAIN = 4,
};

#include "jc_voronoi.h"
#include "tph_poisson.h"

struct VoronoiCell
{
	enum VoronoiCellType cell_type;
	float noise_value;
	const struct jcv_site_ *site;
};

struct Grid
{
	struct jcv_diagram_ *voronoi_grid; // read-only
	struct VoronoiCell *voronoi_cells; // read-write
};

struct MapSettings
{
	float size;
	int seed;
};

struct VoronoiSettings
{
	float radius;
	int num_relaxations;
};

typedef void(CPP_NODES_API *PFN_generate_voronoi_map)(const struct MapSettings *map_settings, const struct VoronoiSettings *voronoi_settings, struct Grid *grid);
typedef void(CPP_NODES_API *PFN_generate_landscape_from_image)(struct Grid *grid, const char *image_path);
typedef void(CPP_NODES_API *PFN_generate_landscape)(const struct MapSettings *settings, struct Grid *grid);
typedef unsigned char *(CPP_NODES_API *PFN_generate_landscape_preview)(struct Grid *grid, unsigned int image_width, unsigned int image_height);
