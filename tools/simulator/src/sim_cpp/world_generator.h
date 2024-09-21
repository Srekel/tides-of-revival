#pragma once

// #include "jc_voronoi.h"
// #include <inttypes.h>

enum map_cell_type_t
{
	NONE = 0,
	WATER = 1,
	LAND = 2,
	SHORE = 3,
	MOUNTAIN = 4,
};

struct jcv_site_;
struct jcv_diagram_;

struct map_cell_t
{
	map_cell_type_t cell_type;
	float noise_value;
	const jcv_site_ *site;
};

struct grid_t
{
	jcv_diagram_ *voronoi_grid; // read-only
	map_cell_t *voronoi_cells;	// read-write
};

struct map_settings_t
{
	float size;
	float radius;
	int num_relaxations;
	int seed;
	// Shape noise settings
	int landscape_seed;
	float landscape_frequency;
	int landscape_octaves;
	float landscape_lacunarity;
};

void generate_voronoi_map(map_settings_t settings, grid_t *grid);
void generate_landscape_from_image(map_settings_t settings, const char *image_path, grid_t *grid);
void generate_landscape(map_settings_t settings, grid_t *grid);

// NOTE: Utility function, not a mutator
unsigned char *generate_landscape_preview(grid_t *grid, unsigned int image_width, unsigned int image_height);
