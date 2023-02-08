const std = @import("std");
const IdLocal = @import("../variant.zig").IdLocal;

const LoD = u4;
const min_patch_size = 64; // 2^6 m
const max_patch_size = 8192; // 2^(6+7) m
const max_world_size = 512 * 1024; // 500 km
const max_patch = max_world_size / min_patch_size; // 8k patches
const max_patch_int_bits = 16; // 2**13 = 8k
const max_patch_int = std.meta.Int(.unsigned, max_patch_int_bits);

const max_requesters = 8;
const max_patch_types = 8;
const Priority = u8;
const RequesterId = u8;
const PatchType = u8;

const PatchRequest = struct {
    requester_id: u64,
    priority: Priority,
};

// const PatchLookup = u32;
// fn calcPatchLookup(x: u32, z: u32, lod: LoD) u32 {
//     const res = x | (z << max_patch_int_bits) | (lod << (max_patch_int_bits * 2));
//     return res;
// }
const PatchLookup = struct {
    x: max_patch_int,
    z: max_patch_int,
    lod: LoD,
    patch_type: PatchType,

    // comptime {
    //     std.debug.assert(@sizeOf(@This()) == @sizeOf(u32));
    // }
};

// pub const PatchLookupHashContext = struct {
//     pub fn hash(self: @This(), pl: PatchLookup) u32 {
//         _ = self;
//         return @ptrCast();
//     }
//     pub fn eql(self: @This(), a: PatchLookup, b: PatchLookup, b_index: usize) bool {
//         _ = self;
//         _ = b_index;
//         return eqlString(a, b);
//     }
// };

const Patch = struct {
    data: ?[]u8 = null,
    requesters: [max_requesters]PatchRequest = undefined,
    request_count: u8 = 0,
    highest_prio: Priority = 0,
};

const RequestArea = struct {
    x: f32,
    z: f32,
    width: f32,
    height: f32,
};

const WorldPatchManager = struct {
    comptime lod_0_patch_size: comptime_float = undefined,
    allocator: std.Allocator,
    requesters: std.ArrayList(IdLocal),
    patch_map: std.AutoArrayHashMap(PatchLookup, Patch),
    patch_queue: std.PriorityQueue(QueuedPatch),

    pub fn create(allocator: std.Allocator, lod_0_patch_size: comptime_float) WorldPatchManager {
        var res = WorldPatchManager{
            .lod_0_patch_size = lod_0_patch_size,
            .allocator = allocator,
        };
        res.requesters.ensureTotalCapacity(max_requesters);
        return res;
    }

    pub fn registerRequester(self: *WorldPatchManager, id: IdLocal) RequesterId {
        const requester_id = @intCast(u8, self.requesters.items.len);
        self.requesters.addOneAssumeCapacity(id);
        return requester_id;
    }

    pub fn addLoadRequest(self: *WorldPatchManager, requester_id: RequesterId, patch_type: PatchType, area: RequestArea, lod: LoD, prio: Priority) void {
        const world_stride = self.lod_0_patch_size * std.math.pow(f32, @intToFloat(f32, lod), 2);
        const world_x_begin = @divFloor(area.x, world_stride);
        const world_z_begin = @divFloor(area.z, world_stride);
        const world_x_end = @divFloor(area.x + area.width - 1, world_stride) + 1;
        const world_z_end = @divFloor(area.z + area.height - 1, world_stride) + 1;
        const patch_x_begin = @divExact(world_x_begin, world_stride);
        const patch_z_begin = @divExact(world_z_begin, world_stride);
        const patch_x_end = @divExact(world_x_end, world_stride);
        const patch_z_end = @divExact(world_z_end, world_stride);

        var patch_z = patch_z_begin;
        while (patch_z < patch_z_end) {
            var patch_x = patch_x_begin;
            while (patch_x < patch_x_end) {
                const patch_lookup = PatchLookup{
                    .x = patch_x,
                    .z = patch_z,
                    .lod = lod,
                    .patch_type = patch_type,
                };

                const patch_opt = self.patch_map.get(patch_lookup);
                if (patch_opt) |*patch| {
                    patch.requesters[patch.request_count].id = requester_id;
                    patch.requesters[patch.request_count].prio = prio;
                    patch.request_count += 1;
                    patch.prio = std.math.max(patch.prio, prio);
                    continue;
                }

                const patch = Patch{};
                patch.request_count = 1;
                patch.prio = prio;
                self.patch_map.put(patch_lookup, patch);

                // TODO: Add to queue
            }
        }
    }

    pub fn removeLoadRequest(self: *WorldPatchManager, requester_id: RequesterId, patch_type: PatchType, area: RequestArea, lod: LoD, prio: Priority) void {
        const world_stride = self.lod_0_patch_size * std.math.pow(f32, @intToFloat(f32, lod), 2);
        const world_x_begin = @divFloor(area.x, world_stride);
        const world_z_begin = @divFloor(area.z, world_stride);
        const world_x_end = @divFloor(area.x + area.width - 1, world_stride) + 1;
        const world_z_end = @divFloor(area.z + area.height - 1, world_stride) + 1;
        const patch_x_begin = @divExact(world_x_begin, world_stride);
        const patch_z_begin = @divExact(world_z_begin, world_stride);
        const patch_x_end = @divExact(world_x_end, world_stride);
        const patch_z_end = @divExact(world_z_end, world_stride);

        var patch_z = patch_z_begin;
        while (patch_z < patch_z_end) {
            var patch_x = patch_x_begin;
            while (patch_x < patch_x_end) {
                const patch_lookup = PatchLookup{
                    .x = patch_x,
                    .z = patch_z,
                    .lod = lod,
                    .patch_type = patch_type,
                };

                const patch_opt = self.patch_map.remove(patch_lookup);
                if (patch_opt) |*patch| {
                    for (patch.requesters) |*requester, i| {
                        if (requester.id == requester_id) {
                            if (requester.prio == patch.highest_prio) {
                                // TODO: Update highest
                            }
                            requester = patch.requesters[patch.request_count - 1];
                            patch.request_count -= 1;

                            if (patch.request_count == 0) {
                                // TODO: Remove from queue
                            }

                            break;
                        }
                    }
                }
            }
        }
    }

    fn tryGetPatch(self: WorldPatchManager, patch_lookup: PatchLookup, T: type) ?[]T {
        const patch_opt = self.patch_map.get(patch_lookup);
        if (patch_opt) |patch| {
            return patch.data;
        }
        return null;
    }
};
