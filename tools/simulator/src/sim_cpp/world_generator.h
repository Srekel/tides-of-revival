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
	SHORE = 2,
	PLAINS = 3,
	HILLS = 4,
	MOUNTAINS = 5,
};

#include "jc_voronoi.h"
#include "tph_poisson.h"

struct VoronoiCell
{
	enum VoronoiCellType cell_type;
	float noise_value;
	const struct jcv_site_ *site;
};

struct Voronoi
{
	struct jcv_diagram_ voronoi_grid;  // read-only
	struct VoronoiCell *voronoi_cells; // read-write
};

struct VoronoiSettings
{
	float size;
	int seed;
	float radius;
	int num_relaxations;
};

typedef void(CPP_NODES_API *PFN_generate_landscape_from_image)(struct Voronoi *grid, const char *image_path);
typedef unsigned char *(CPP_NODES_API *PFN_generate_landscape_preview)(struct Voronoi *grid, unsigned int image_width, unsigned int image_height);
typedef float *(CPP_NODES_API *PFN_voronoi_to_imagef32)(struct Voronoi *grid, unsigned int image_width, unsigned int image_height);
