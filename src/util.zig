const std = @import("std");
const ecs = @import("zflecs");
const fd = @import("config/flecs_data.zig");
const znoise = @import("znoise");
const v = @import("core/variant.zig");
const context = @import("core/context.zig");
const ecsu = @import("flecs_util/flecs_util.zig");

pub const Context = context.Context;

pub fn sliceOfInstance(comptime T: type, instance: *T) []T {
    const arrptr: *[1]T = instance;
    const slice: []T = arrptr;
    return slice;
}

pub fn sliceOfInstanceConst(comptime T: type, instance: *const T) []const T {
    const arrptr: *const [1]T = instance;
    const slice: []const T = arrptr;
    return slice;
}

pub fn asConstSentinelTerminated(string_ptr: [*:0]u8) [:0]const u8 {
    const string_len = std.mem.len(string_ptr);
    return @as([:0]const u8, @ptrCast(string_ptr[0..string_len]));
}

pub fn fromCStringToStringSlice(string_ptr: [*:0]u8) []const u8 {
    const string_len = std.mem.len(string_ptr);
    return @as([]const u8, @ptrCast(string_ptr[0..string_len]));
}

// pub fn sliceOfInstance2(comptime T: type, instance: *T) []T {
//     var slice: []T = undefined;
//     slice.ptr = @ptrCast([*]T, instance);
//     slice.len = 1;
//     return slice;
// }

pub fn castBytes(comptime T: type, slice: []u8) *T {
    const ptr = std.mem.bytesAsValue(T, slice[0..@sizeOf(T)]);
    return @alignCast(ptr);
}

pub fn castOpaque(comptime T: type, ptr: *anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ptr)));
}

pub fn castSliceToSlice(comptime T: type, slice: anytype) []T {
    // Note; This is a workaround for @ptrCast not supporting this
    const bytes = std.mem.sliceAsBytes(slice);
    const new_slice = std.mem.bytesAsSlice(T, bytes);
    return new_slice;
}

pub fn castOpaqueConst(comptime T: type, ptr: *const anyopaque) *const T {
    return @as(*const T, @ptrCast(@alignCast(ptr)));
}

pub fn memcpy(dst: *anyopaque, src: *const anyopaque, byte_count: u64) void {
    const src_slice = @as([*]const u8, @ptrCast(src))[0..byte_count];
    const dst_slice = @as([*]u8, @ptrCast(dst))[0..byte_count];
    for (src_slice, 0..) |byte, i| {
        dst_slice[i] = byte;
    }
}

pub fn log(str: []const u8) void {
    std.log.debug("{str}", .{str});
}
pub fn log1(obj1name: []const u8, obj1: anytype) void {
    std.log.debug("{str}:{any}", .{ obj1name, obj1 });
}
pub fn log2(obj1name: []const u8, obj1: anytype, obj2name: []const u8, obj2: anytype) void {
    std.log.debug("{str}:{any}, {str}:{any}", .{ obj1name, obj1, obj2name, obj2 });
}
pub fn log3(obj1name: []const u8, obj1: anytype, obj2name: []const u8, obj2: anytype, obj3name: []const u8, obj3: anytype) void {
    std.log.debug("{str}:{any}, {str}:{any}, {str}:{any}", .{ obj1name, obj1, obj2name, obj2, obj3name, obj3 });
}

pub fn heightAtXZ(world_x: f32, world_z: f32, noise_scale_xz: f32, noise_scale_y: f32, noise_offset_y: f32, noise: *const znoise.FnlGenerator) f32 {
    // _ = noise_scale_xz;
    // _ = noise_scale_y;
    // _ = noise_offset_y;
    // _ = noise;
    // return 100 + 10 * (@sin(world_x * 0.01) + @cos(world_z * 0.01)) + 2 * (@sin(world_x * 0.1) + @cos(world_z * 0.1));
    return noise_scale_y * (noise_offset_y + noise.noise2(world_x * noise_scale_xz, world_z * noise_scale_xz) + 1) * 0.5;
}

pub fn getActiveCameraEnt(ecsu_world: ecsu.World) ecsu.Entity {
    const environment_info = ecsu_world.getSingleton(fd.EnvironmentInfo);
    return environment_info.?.active_camera.?;
}

pub fn getSkyLight(ecsu_world: ecsu.World) ?ecsu.Entity {
    const environment_info = ecsu_world.getSingleton(fd.EnvironmentInfo);
    if (environment_info) |info| {
        return info.sky_light;
    }

    return null;
}

pub fn getSun(ecsu_world: ecsu.World) ?ecsu.Entity {
    const environment_info = ecsu_world.getSingleton(fd.EnvironmentInfo);
    if (environment_info) |info| {
        return info.sun;
    }

    return null;
}

// pub fn applyTransformRecursively(
//     ent: flecs.Entity,
//     parent_pos: fd.WorldPosition,
//     parent_rot: fd.Rotation,
//     ecsu_world: ecs.world_t,
// ) void {
//     if (ent.getMut(fd.Position)) |pos| {
//         if (ent.getMut(fd.Rotation)) |rot| {
//             pos.x += parent_pos.x;
//             pos.y += parent_pos.y;
//             // Calculate actual position
//             const p_actual = .{
//                 .x = position.x + p_parent.x,
//                 .y = position.y + p_parent.y,
//             };
//             std.log.debug("{s}: {d}", .{ e.getName(), p_actual });

//             // Iterate children recursively
//             var term = flecs.Term({}).initWithPair(world, world.pair(ecs.ChildOf, e.id));
//             var iter = term.entityIterator();
//             while (iter.next()) |entity| {
//                 iterateTree(world, entity, p_actual);
//             }
//         }
//     }
// }

// pub fn applyTransform(entity: flecs.Entity, ecsu_world: ecsu.World) void {
//     const FilterCallback = struct {
//         position: *const Position,
//     };

//     const root_pos = fd.Position.init(0, 0, 0);
//     for (entities) |ent| {
//         var filter = world.filterParent(FilterCallback, ent);
//         var iter = filter.iterator(FilterCallback);
//         const p_actual = .{ .x = position.x + p_parent.x, .y = position.y + p_parent.y };

//         var term = flecs.Term({}).initWithPair(world, world.pair(ecs.ChildOf, e.id));
//         var iter = term.entityIterator();
//         while (iter.next()) |child_ent| {
//             iterateTree(world, child_ent, p_actual);
//         }
//     }
// }
