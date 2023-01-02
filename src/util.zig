const std = @import("std");
const flecs = @import("flecs");
const fd = @import("flecs_data.zig");
const znoise = @import("znoise");

pub fn castBytes(comptime T: type, slice: []u8) *T {
    const ptr = std.mem.bytesAsValue(T, slice[0..@sizeOf(T)]);
    return @alignCast(@alignOf(T), ptr);
}

pub fn castOpaque(comptime T: type, ptr: *anyopaque) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), ptr));
}

pub fn memcpy(dst: *anyopaque, src: *const anyopaque, byte_count: u64) void {
    const src_slice = @ptrCast([*]const u8, src)[0..byte_count];
    const dst_slice = @ptrCast([*]u8, dst)[0..byte_count];
    for (src_slice) |byte, i| {
        dst_slice[i] = byte;
    }
}

pub fn heightAtXZ(world_x: f32, world_z: f32, noise_scale_xz: f32, noise_scale_y: f32, noise_offset_y: f32, noise: *const znoise.FnlGenerator) f32 {
    // _ = noise_scale_xz;
    // _ = noise_scale_y;
    // _ = noise_offset_y;
    // _ = noise;
    // return 100 + 10 * (@sin(world_x * 0.01) + @cos(world_z * 0.01)) + 2 * (@sin(world_x * 0.1) + @cos(world_z * 0.1));
    return noise_scale_y * (noise_offset_y + noise.noise2(world_x * noise_scale_xz, world_z * noise_scale_xz));
}

// pub fn applyTransformRecursively(
//     ent: flecs.Entity,
//     parent_pos: fd.WorldPosition,
//     parent_rot: fd.EulerRotation,
//     flecs_world: flecs.World,
// ) void {
//     if (ent.getMut(fd.Position)) |pos| {
//         if (ent.getMut(fd.EulerRotation)) |rot| {
//             pos.x += parent_pos.x;
//             pos.y += parent_pos.y;
//             // Calculate actual position
//             const p_actual = .{
//                 .x = position.x + p_parent.x,
//                 .y = position.y + p_parent.y,
//             };
//             std.log.debug("{s}: {d}", .{ e.getName(), p_actual });

//             // Iterate children recursively
//             var term = flecs.Term({}).initWithPair(world, world.pair(flecs.c.EcsChildOf, e.id));
//             var iter = term.entityIterator();
//             while (iter.next()) |entity| {
//                 iterateTree(world, entity, p_actual);
//             }
//         }
//     }
// }

// pub fn applyTransform(entity: flecs.Entity, flecs_world: *flecs.World) void {
//     const FilterCallback = struct {
//         position: *const Position,
//     };

//     const root_pos = fd.Position.init(0, 0, 0);
//     for (entities) |ent| {
//         var filter = world.filterParent(FilterCallback, ent);
//         var iter = filter.iterator(FilterCallback);
//         const p_actual = .{ .x = position.x + p_parent.x, .y = position.y + p_parent.y };

//         var term = flecs.Term({}).initWithPair(world, world.pair(flecs.c.EcsChildOf, e.id));
//         var iter = term.entityIterator();
//         while (iter.next()) |child_ent| {
//             iterateTree(world, child_ent, p_actual);
//         }
//     }
// }
