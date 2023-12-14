const std = @import("std");
const g = @import("graph.zig");
const v = @import("../../core/core.zig").variant;
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
        count_z: u64 = undefined,

        pub fn getValue(self: Self, world_x: anytype, world_z: anytype) PatchElement {
            const patch_x = @divTrunc(@as(u64, world_x), self.patch_width);
            const patch_z = @divTrunc(@as(u64, world_z), self.patch_width);
            // const patch_begin_x = @divExact(@intCast(u64, self.patch_positions[0][0]), self.patch_width);
            // const patch_begin_z = @divExact(@intCast(u64, self.patch_positions[0][1]), self.patch_width);
            const patch_begin_x = @as(u64, self.patch_positions[0][0]);
            const patch_begin_z = @as(u64, self.patch_positions[0][1]);
            const patch_index_x = patch_x - patch_begin_x;
            const patch_index_z = patch_z - patch_begin_z;
            const patch = self.patches[patch_index_x + patch_index_z * self.count_x];
            const inside_patch_x = @as(u64, world_x) % self.patch_width;
            const inside_patch_z = @as(u64, world_z) % self.patch_width;
            return patch[inside_patch_x + inside_patch_z * self.patch_width];
        }

        pub fn getHeightI(self: Self, world_x: i64, world_z: i64) i32 {
            return self.getHeight(world_x, world_z);
        }

        pub fn getValueDynamic(self: Self, world_x: i64, world_z: i64, comptime ActualPatchElement: type) ActualPatchElement {
            const patch_x = @divTrunc(@as(u64, @intCast(world_x)), self.patch_width);
            const patch_z = @divTrunc(@as(u64, @intCast(world_z)), self.patch_width);
            const patch_begin_x = @as(u64, @intCast(self.patch_positions[0][0]));
            const patch_begin_z = @as(u64, @intCast(self.patch_positions[0][1]));
            const patch_index_x = patch_x - patch_begin_x;
            const patch_index_z = patch_z - patch_begin_z;
            const patch = self.patches[patch_index_x + patch_index_z * self.count_x];

            // TODO: use ptrCast when this is fixed:
            // in sema.zig: "TODO: implement @ptrCast between slices changing the length"
            const actual_patch_opaque: *anyopaque = @ptrCast(patch.ptr);
            const actual_patch_opaque_aligned: *align(@alignOf(ActualPatchElement)) anyopaque = @alignCast(actual_patch_opaque);
            const actual_patch_ptr: [*]ActualPatchElement = @ptrCast(actual_patch_opaque_aligned);
            const actual_patch: []ActualPatchElement = @ptrCast(actual_patch_ptr[0..patch.len]);
            const inside_patch_x = @as(u64, @intCast(world_x)) % self.patch_width;
            const inside_patch_z = @as(u64, @intCast(world_z)) % self.patch_width;
            return actual_patch[inside_patch_x + inside_patch_z * self.patch_width];
        }
    };
    return res;
}
