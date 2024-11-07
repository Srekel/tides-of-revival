#include "world_generator.h"
#include "world_generator_core.h"

// #define FNL_IMPL
// #include "FastNoiseLite.h"

#define JC_VORONOI_IMPLEMENTATION
#include "jc_voronoi.h"
#define JC_VORONOI_CLIP_IMPLEMENTATION
#include "jc_voronoi_clip.h"
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

float g_landscapeWaterColor[3] = {0.0f, 0.5f, 1.0f};
float g_landscapeLandColor[3] = {0.15f, 0.5f, 0.0f};
float g_landscapeShoreColor[3] = {1.0f, 0.0f, 0.0f};
float g_landscapeMountainColor[3] = {0.5f, 0.5f, 0.5f};

static inline jcv_point remap(const jcv_point *pt, const jcv_point *min, const jcv_point *max, const jcv_point *scale);
static void draw_triangle(const jcv_point *v0, const jcv_point *v1, const jcv_point *v2, unsigned char *image, int width, int height, int nchannels, unsigned char *color);

void generate_landscape_from_image(Voronoi *grid, const char *image_path)
{
	int image_width, image_height, image_channels;
	stbi_set_flip_vertically_on_load(true);
	unsigned char *image_data = stbi_load(image_path, &image_width, &image_height, &image_channels, 0);
	assert(image_data);

	const jcv_site *sites = jcv_diagram_get_sites(&grid->voronoi_grid);
	for (int i = 0; i < grid->voronoi_grid.numsites; ++i)
	{
		const jcv_site *site = &sites[i];
		VoronoiCell &cell = grid->voronoi_cells[site->index];
		cell.site = site;

		// P is in the voronoi diagram space, we need to convert it to the image space
		float uv_x = site->p.x / (float)grid->voronoi_grid.max.x;
		float uv_y = site->p.y / (float)grid->voronoi_grid.max.y;
		int image_x = (int)(uv_x * image_width);
		int image_y = (int)(uv_y * image_height);
		assert(image_x >= 0 && image_x < image_width);
		assert(image_y >= 0 && image_y < image_height);

		unsigned char *sample = &image_data[(image_x + image_y * image_width) * image_channels];
		if (sample[0] == 38 && sample[1] == 127 && sample[2] == 0)
		{
			cell.cell_type = LAND;
		}
		else if (sample[0] == 0 && sample[1] == 148 && sample[2] == 255)
		{
			cell.cell_type = WATER;
		}
		else if (sample[0] == 128 && sample[1] == 128 && sample[2] == 128)
		{
			cell.cell_type = MOUNTAIN;
		}
		else
		{
			cell.cell_type = LAND;
		}
	}

	stbi_image_free(image_data);
}

void generate_landscape(const VoronoiSettings *settings, Voronoi *grid)
{
	// fnl_state noise = fnlCreateState();
	// noise.noise_type = FNL_NOISE_OPENSIMPLEX2;
	// noise.seed = settings->landscape_seed;
	// noise.octaves = settings->landscape_octaves;
	// noise.frequency = settings->landscape_frequency;

	// jcv_point center;
	// const float landscape_radius = settings->size / 2.0f - 0.5f;
	// const float squared_radius = landscape_radius * landscape_radius;
	// center.x = settings->size / 2.0f;
	// center.y = settings->size / 2.0f;

	// const jcv_site *sites = jcv_diagram_get_sites(grid->voronoi_grid);
	// for (int i = 0; i < grid->voronoi_grid.numsites; ++i)
	// {
	// 	const jcv_site *site = &sites[i];
	// 	VoronoiCell &cell = grid->voronoi_cells[site->index];
	// 	cell.site = site;

	// 	float squared_distance = (site->p.x - center.x) * (site->p.x - center.x) + (site->p.y - center.y) * (site->p.y - center.y);
	// 	cell.noise_value = fnlGetNoise2D(&noise, site->p.x, site->p.y);

	// 	if (squared_distance <= squared_radius && cell.noise_value >= 0.2f)
	// 	{
	// 		cell.cell_type = LAND;
	// 	}
	// 	else
	// 	{
	// 		cell.cell_type = WATER;
	// 	}
	// }

	// for (int i = 0; i < grid->voronoi_grid.numsites; ++i)
	// {
	// 	const jcv_site *site = &sites[i];
	// 	VoronoiCell &cell = grid->voronoi_cells[site->index];
	// 	if (cell.cell_type == WATER)
	// 	{
	// 		const jcv_graphedge *edge = site->edges;
	// 		while (edge)
	// 		{
	// 			if (edge->neighbor != nullptr)
	// 			{
	// 				int cell_index = edge->neighbor->index;
	// 				VoronoiCell &neighbor = grid->voronoi_cells[cell_index];
	// 				if (neighbor.cell_type == LAND)
	// 				{
	// 					cell.cell_type = SHORE;
	// 					break;
	// 				}
	// 			}

	// 			edge = edge->next;
	// 		}
	// 	}
	// }
}

static inline jcv_point remap(const jcv_point *pt, const jcv_point *min, const jcv_point *max, const jcv_point *scale)
{
	jcv_point p;
	p.x = (pt->x - min->x) / (max->x - min->x) * scale->x;
	p.y = (pt->y - min->y) / (max->y - min->y) * scale->y;
	return p;
}

// http://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/
static inline int orient2d(const jcv_point *a, const jcv_point *b, const jcv_point *c)
{
	return ((int)b->x - (int)a->x) * ((int)c->y - (int)a->y) - ((int)b->y - (int)a->y) * ((int)c->x - (int)a->x);
}

static inline int min2(int a, int b)
{
	return (a < b) ? a : b;
}

static inline int max2(int a, int b)
{
	return (a > b) ? a : b;
}

static inline int min3(int a, int b, int c)
{
	return min2(a, min2(b, c));
}
static inline int max3(int a, int b, int c)
{
	return max2(a, max2(b, c));
}

static void plot(int x, int y, unsigned char *image, int width, int height, int nchannels, unsigned char *color)
{
	if (x < 0 || y < 0 || x > (width - 1) || y > (height - 1))
		return;
	int index = y * width * nchannels + x * nchannels;
	for (int i = 0; i < nchannels; ++i)
	{
		image[index + i] = color[i];
	}
}

static void draw_triangle(const jcv_point *v0, const jcv_point *v1, const jcv_point *v2, unsigned char *image,
						  int width, int height, int nchannels, unsigned char *color)
{
	int area = orient2d(v0, v1, v2);
	if (area == 0)
		return;

	// Compute triangle bounding box
	int minX = min3((int)v0->x, (int)v1->x, (int)v2->x);
	int minY = min3((int)v0->y, (int)v1->y, (int)v2->y);
	int maxX = max3((int)v0->x, (int)v1->x, (int)v2->x);
	int maxY = max3((int)v0->y, (int)v1->y, (int)v2->y);

	// Clip against screen bounds
	minX = max2(minX, 0);
	minY = max2(minY, 0);
	maxX = min2(maxX, width - 1);
	maxY = min2(maxY, height - 1);

	// Rasterize
	jcv_point p;
	for (p.y = (jcv_real)minY; p.y <= (jcv_real)maxY; p.y++)
	{
		for (p.x = (jcv_real)minX; p.x <= (jcv_real)maxX; p.x++)
		{
			// Determine barycentric coordinates
			int w0 = orient2d(v1, v2, &p);
			int w1 = orient2d(v2, v0, &p);
			int w2 = orient2d(v0, v1, &p);

			// If p is on or inside all edges, render pixel.
			if (w0 >= 0 && w1 >= 0 && w2 >= 0)
			{
				plot((int)p.x, (int)p.y, image, width, height, nchannels, color);
			}
		}
	}
}

unsigned char *generate_landscape_preview(Voronoi *grid, uint32_t image_width, uint32_t image_height)
{
	size_t imagesize = (size_t)(image_width * image_height * 4);
	unsigned char *image = (unsigned char *)malloc(imagesize);
	memset(image, 0, imagesize);

	unsigned char color_pt[] = {255, 255, 255};
	unsigned char color_line[] = {220, 220, 220};
	unsigned char color_delauney[] = {64, 64, 255};

	jcv_point dimensions;
	dimensions.x = (jcv_real)image_width;
	dimensions.y = (jcv_real)image_height;

	{
		const jcv_site *sites = jcv_diagram_get_sites(&grid->voronoi_grid);
		for (int i = 0; i < grid->voronoi_grid.numsites; ++i)
		{
			const jcv_site *site = &sites[i];
			srand((unsigned int)site->index);

			VoronoiCell &cell = grid->voronoi_cells[site->index];
			unsigned char color_tri[4];
			color_tri[0] = color_tri[1] = color_tri[2] = (int)(cell.noise_value * 255.0f);
			color_tri[3] = 255;
			if (cell.cell_type == LAND)
			{
				color_tri[0] = (unsigned char)(g_landscapeLandColor[0] * 255.0f);
				color_tri[1] = (unsigned char)(g_landscapeLandColor[1] * 255.0f);
				color_tri[2] = (unsigned char)(g_landscapeLandColor[2] * 255.0f);
			}
			else if (cell.cell_type == WATER)
			{
				color_tri[0] = (unsigned char)(g_landscapeWaterColor[0] * 255.0f);
				color_tri[1] = (unsigned char)(g_landscapeWaterColor[1] * 255.0f);
				color_tri[2] = (unsigned char)(g_landscapeWaterColor[2] * 255.0f);
			}
			else if (cell.cell_type == SHORE)
			{
				color_tri[0] = (unsigned char)(g_landscapeShoreColor[0] * 255.0f);
				color_tri[1] = (unsigned char)(g_landscapeShoreColor[1] * 255.0f);
				color_tri[2] = (unsigned char)(g_landscapeShoreColor[2] * 255.0f);
			}

			jcv_point s = remap(&site->p, &grid->voronoi_grid.min, &grid->voronoi_grid.max, &dimensions);

			const jcv_graphedge *e = site->edges;
			while (e)
			{
				jcv_point p0 = remap(&e->pos[0], &grid->voronoi_grid.min, &grid->voronoi_grid.max, &dimensions);
				jcv_point p1 = remap(&e->pos[1], &grid->voronoi_grid.min, &grid->voronoi_grid.max, &dimensions);

				draw_triangle(&s, &p0, &p1, image, image_width, image_width, 4, color_tri);
				e = e->next;
			}
		}
	}

	// flip image
	int stride = image_width * 4;
	uint8_t *row = (uint8_t *)malloc((size_t)stride);
	for (int y = 0; y < (int32_t)image_height / 2; ++y)
	{
		memcpy(row, &image[y * stride], (size_t)stride);
		memcpy(&image[y * stride], &image[(image_height - 1 - y) * stride], (size_t)stride);
		memcpy(&image[(image_height - 1 - y) * stride], row, (size_t)stride);
	}

	return image;
}
