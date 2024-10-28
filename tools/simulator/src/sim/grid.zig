const types = @import("types.zig");

pub const Grid = struct {
    size: types.Size2D,
    cell_size: u64, // only square cells
};
