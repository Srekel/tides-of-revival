const std = @import("std");
const math = std.math;
const zm = @import("zmath");
const zphy = @import("zphysics");
const ztracy = @import("ztracy");

const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
// const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
// const tides_math = @import("../core/math.zig");
const config = @import("../config/config.zig");
const util = @import("../util.zig");
const EventManager = @import("../core/event_manager.zig").EventManager;
const context = @import("../core/context.zig");
const patch_types = @import("../worldpatch/patch_types.zig");

const patch_side_vertex_count = config.patch_resolution;
const vertices_per_patch: u32 = patch_side_vertex_count * patch_side_vertex_count;
const indices_per_patch: u32 = (config.patch_resolution - 1) * (config.patch_resolution - 1) * 6;

const object_layers = config.object_layers;
const broad_phase_layers = config.broad_phase_layers;

const BroadPhaseLayerInterface = extern struct {
    usingnamespace zphy.BroadPhaseLayerInterface.Methods(@This());
    __v: *const zphy.BroadPhaseLayerInterface.VTable = &vtable,

    object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = undefined,

    const vtable = zphy.BroadPhaseLayerInterface.VTable{
        .getNumBroadPhaseLayers = _getNumBroadPhaseLayers,
        .getBroadPhaseLayer = switch (@import("builtin").abi) {
            .msvc => _getBroadPhaseLayer_msvc,
            else => _getBroadPhaseLayer,
        },
    };

    fn init() BroadPhaseLayerInterface {
        var layer_interface: BroadPhaseLayerInterface = .{};
        layer_interface.object_to_broad_phase[object_layers.non_moving] = broad_phase_layers.non_moving;
        layer_interface.object_to_broad_phase[object_layers.moving] = broad_phase_layers.moving;
        return layer_interface;
    }

    fn _getNumBroadPhaseLayers(_: *const zphy.BroadPhaseLayerInterface) callconv(.C) u32 {
        return broad_phase_layers.len;
    }

    fn _getBroadPhaseLayer(
        iself: *const zphy.BroadPhaseLayerInterface,
        layer: zphy.ObjectLayer,
    ) callconv(.C) zphy.BroadPhaseLayer {
        const self = @as(*const BroadPhaseLayerInterface, @ptrCast(iself));
        return self.object_to_broad_phase[layer];
    }

    fn _getBroadPhaseLayer_msvc(
        iself: *const zphy.BroadPhaseLayerInterface,
        out_layer: *zphy.BroadPhaseLayer,
        layer: zphy.ObjectLayer,
    ) callconv(.C) *const zphy.BroadPhaseLayer {
        const self = @as(*const BroadPhaseLayerInterface, @ptrCast(iself));
        out_layer.* = self.object_to_broad_phase[layer];
        return &self.object_to_broad_phase[layer];
    }
};

const ObjectVsBroadPhaseLayerFilter = extern struct {
    usingnamespace zphy.ObjectVsBroadPhaseLayerFilter.Methods(@This());
    __v: *const zphy.ObjectVsBroadPhaseLayerFilter.VTable = &vtable,

    const vtable = zphy.ObjectVsBroadPhaseLayerFilter.VTable{ .shouldCollide = _shouldCollide };

    fn _shouldCollide(
        _: *const zphy.ObjectVsBroadPhaseLayerFilter,
        layer1: zphy.ObjectLayer,
        layer2: zphy.BroadPhaseLayer,
    ) callconv(.C) bool {
        return switch (layer1) {
            object_layers.non_moving => layer2 == broad_phase_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ObjectLayerPairFilter = extern struct {
    usingnamespace zphy.ObjectLayerPairFilter.Methods(@This());
    __v: *const zphy.ObjectLayerPairFilter.VTable = &vtable,

    const vtable = zphy.ObjectLayerPairFilter.VTable{ .shouldCollide = _shouldCollide };

    fn _shouldCollide(
        _: *const zphy.ObjectLayerPairFilter,
        object1: zphy.ObjectLayer,
        object2: zphy.ObjectLayer,
    ) callconv(.C) bool {
        return switch (object1) {
            object_layers.non_moving => object2 == object_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const PhysicsManager = struct {
    heap_allocator: std.mem.Allocator,
    physics_world: *zphy.PhysicsSystem,
    physics_world_low: *zphy.PhysicsSystem,
};

pub fn create(arena_lifetime: std.mem.Allocator, heap_allocator: std.mem.Allocator) PhysicsManager {
    const broad_phase_layer_interface = arena_lifetime.create(BroadPhaseLayerInterface) catch unreachable;
    broad_phase_layer_interface.* = BroadPhaseLayerInterface.init();

    const object_vs_broad_phase_layer_filter = arena_lifetime.create(ObjectVsBroadPhaseLayerFilter) catch unreachable;
    object_vs_broad_phase_layer_filter.* = .{};

    const object_layer_pair_filter = arena_lifetime.create(ObjectLayerPairFilter) catch unreachable;
    object_layer_pair_filter.* = .{};

    zphy.init(heap_allocator, .{}) catch unreachable;
    const physics_world = zphy.PhysicsSystem.create(
        @as(*const zphy.BroadPhaseLayerInterface, @ptrCast(broad_phase_layer_interface)),
        @as(*const zphy.ObjectVsBroadPhaseLayerFilter, @ptrCast(object_vs_broad_phase_layer_filter)),
        @as(*const zphy.ObjectLayerPairFilter, @ptrCast(object_layer_pair_filter)),
        .{
            .max_bodies = 16 * 1024,
            .num_body_mutexes = 0,
            .max_body_pairs = 16 * 1024,
            .max_contact_constraints = 16 * 1024,
        },
    ) catch unreachable;

    physics_world.setGravity(.{ 0, -10.0, 0 });

    const physics_world_low = zphy.PhysicsSystem.create(
        @as(*const zphy.BroadPhaseLayerInterface, @ptrCast(broad_phase_layer_interface)),
        @as(*const zphy.ObjectVsBroadPhaseLayerFilter, @ptrCast(object_vs_broad_phase_layer_filter)),
        @as(*const zphy.ObjectLayerPairFilter, @ptrCast(object_layer_pair_filter)),
        .{
            .max_bodies = 16 * 1024,
            .num_body_mutexes = 0,
            .max_body_pairs = 16 * 1024,
            .max_contact_constraints = 16 * 1024,
        },
    ) catch unreachable;

    physics_world_low.setGravity(.{ 0, -10.0, 0 });

    return .{
        .heap_allocator = heap_allocator,
        .physics_world = physics_world,
        .physics_world_low = physics_world_low,
    };
}

pub fn destroy(physics_mgr: *PhysicsManager) void {
    physics_mgr.physics_world_low.destroy();
    physics_mgr.physics_world.destroy();
    zphy.deinit();
}
