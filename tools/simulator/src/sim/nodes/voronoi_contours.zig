const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

pub fn voronoiContours(grid: *c_cpp_nodes.Grid) void {
    const sites = c_cpp_nodes.jcv_diagram_get_sites(grid.voronoi_grid.?);
    for (0..@intCast(grid.voronoi_grid.*.numsites)) |i| {
        const site = &sites[i];
        var cell = &grid.voronoi_cells[@intCast(site.index)];
        if (cell.cell_type == c_cpp_nodes.WATER) {
            var edge = site.edges;
            while (edge != null) {
                if (edge.*.neighbor != null) {
                    const cell_index = edge.*.neighbor.*.index;
                    const neighbor = &grid.voronoi_cells[@intCast(cell_index)];
                    if (neighbor.cell_type == c_cpp_nodes.LAND) {
                        cell.cell_type = c_cpp_nodes.SHORE;
                        break;
                    }
                }

                edge = edge.*.next;
            }
        }
    }
}
