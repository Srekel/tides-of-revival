const core = @import("../core.zig");

pub fn GridSpreader_Step(
    node: core.Mutator,
    grid: *core.Grid_i32,
) void {
    const wanted_cell = node.inputs[0].?.getDataAsObject(u32);

    for (1..grid.size[0] - 1) |z_grid| {
        for (1..grid.size[0] - 1) |x_grid| {
            var count: u32 = 0;
            if (grid[z_grid - 1][x_grid] == wanted_cell) {
                count += 1;
            }
            if (grid[z_grid + 1][x_grid] == wanted_cell) {
                count += 1;
            }
            if (grid[z_grid][x_grid - 1] == wanted_cell) {
                count += 1;
            }
            if (grid[z_grid][x_grid + 1] == wanted_cell) {
                count += 1;
            }

            if (count >= 2) {
                grid[z_grid][x_grid] = 2;
            }
        }
    }
}

// sim.zig

pub fn simulate(graph: *core.Graph) void {
    const node = graph.getMutator(0);
    const grid = graph.getResource(core.Grid_i32);
    GridSpreader_Step(node, grid);
}
