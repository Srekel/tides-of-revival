pub const HeightmapHeight = u16;
pub const HEIGHMAP_PATCH_QUERY_MAX = 32;

pub const HeightmapOutputData = struct {
    patches: [HEIGHMAP_PATCH_QUERY_MAX][]HeightmapHeight = undefined,
    patch_positions: [HEIGHMAP_PATCH_QUERY_MAX][2]i64 = undefined,
    patch_width: u64 = undefined,
    count: u64 = undefined,
    count_x: u64 = undefined,
    count_y: u64 = undefined,

    pub fn getHeight(self: HeightmapOutputData, world_x: i64, world_y: i64) HeightmapHeight {
        const patch_x = @divTrunc(@intCast(u64, world_x), self.patch_width);
        const patch_y = @divTrunc(@intCast(u64, world_y), self.patch_width);
        // const patch_begin_x = @divExact(@intCast(u64, self.patch_positions[0][0]), self.patch_width);
        // const patch_begin_y = @divExact(@intCast(u64, self.patch_positions[0][1]), self.patch_width);
        const patch_begin_x = @intCast(u64, self.patch_positions[0][0]);
        const patch_begin_y = @intCast(u64, self.patch_positions[0][1]);
        const patch_index_x = patch_x - patch_begin_x;
        const patch_index_y = patch_y - patch_begin_y;
        const patch = self.patches[patch_index_x + patch_index_y * self.count_x];
        const inside_patch_x = @intCast(u64, world_x) % self.patch_width;
        const inside_patch_y = @intCast(u64, world_y) % self.patch_width;
        return patch[inside_patch_x + inside_patch_y * self.patch_width];
    }

    pub fn getHeightI(self: HeightmapOutputData, world_x: i64, world_y: i64) i32 {
        return self.getHeight(world_x, world_y);
    }
};
