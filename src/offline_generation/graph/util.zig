const std = @import("std");
const g = @import("graph.zig");
const v = @import("../../variant.zig");
// const g =

pub fn getInputResult(input: *g.NodeInput, context: *g.GraphContext) v.Variant {
    if (input.reference.isUnset()) {
        return input.value;
    } else {
        const prevNodeOutput = input.source orelse unreachable;
        const prevNode = prevNodeOutput.node orelse unreachable;
        const res = prevNode.template.func.func(prevNode, prevNodeOutput, context, &.{});

        if (res != .success) {
            unreachable;
        }
        return res.success;
    }
}

const PATCH_QUERY_MAX = 128;
pub fn PatchOutputData(comptime PatchElement: anytype) type {
    const res = struct {
        const Self = @This();
        patches: [PATCH_QUERY_MAX][]PatchElement = undefined,
        patch_positions: [PATCH_QUERY_MAX][2]i64 = undefined,
        patch_width: u64 = undefined,
        count: u64 = undefined,
        count_x: u64 = undefined,
        count_y: u64 = undefined,

        pub fn getValue(self: Self, world_x: anytype, world_y: anytype) PatchElement {
            const patch_x = @divTrunc(@as(u64, world_x), self.patch_width);
            const patch_y = @divTrunc(@as(u64, world_y), self.patch_width);
            // const patch_begin_x = @divExact(@intCast(u64, self.patch_positions[0][0]), self.patch_width);
            // const patch_begin_y = @divExact(@intCast(u64, self.patch_positions[0][1]), self.patch_width);
            const patch_begin_x = @as(u64, self.patch_positions[0][0]);
            const patch_begin_y = @as(u64, self.patch_positions[0][1]);
            const patch_index_x = patch_x - patch_begin_x;
            const patch_index_y = patch_y - patch_begin_y;
            const patch = self.patches[patch_index_x + patch_index_y * self.count_x];
            const inside_patch_x = @as(u64, world_x) % self.patch_width;
            const inside_patch_y = @as(u64, world_y) % self.patch_width;
            return patch[inside_patch_x + inside_patch_y * self.patch_width];
        }

        pub fn getHeightI(self: Self, world_x: i64, world_y: i64) i32 {
            return self.getHeight(world_x, world_y);
        }

        pub fn getValueDynamic(self: Self, world_x: i64, world_y: i64, comptime ActualPatchElement: type) ActualPatchElement {
            const patch_x = @divTrunc(@as(u64, @intCast(world_x)), self.patch_width);
            const patch_y = @divTrunc(@as(u64, @intCast(world_y)), self.patch_width);
            const patch_begin_x = @as(u64, @intCast(self.patch_positions[0][0]));
            const patch_begin_y = @as(u64, @intCast(self.patch_positions[0][1]));
            const patch_index_x = patch_x - patch_begin_x;
            const patch_index_y = patch_y - patch_begin_y;
            const patch = self.patches[patch_index_x + patch_index_y * self.count_x];
            const actual_patch_width = self.patch_width * @sizeOf(PatchElement) / @sizeOf(ActualPatchElement);
            const actual_patch = std.mem.bytesAsSlice(ActualPatchElement, patch);
            const inside_patch_x = @as(u64, @intCast(world_x)) % actual_patch_width;
            const inside_patch_y = @as(u64, @intCast(world_y)) % actual_patch_width;
            return actual_patch[inside_patch_x + inside_patch_y * actual_patch_width];
        }
    };
    return res;
}
