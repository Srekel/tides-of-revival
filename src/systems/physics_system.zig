const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zm = @import("zmath");
const zphy = @import("zphysics");
const ztracy = @import("ztracy");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
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

const ContactListener = extern struct {
    usingnamespace zphy.ContactListener.Methods(@This());
    __v: *const zphy.ContactListener.VTable = &vtable,
    ctx: *SystemUpdateContext,

    const vtable = zphy.ContactListener.VTable{
        .onContactValidate = _onContactValidate,
        .onContactAdded = _onContactAdded,
    };

    fn _onContactValidate(
        iself: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        base_offset: *const [3]zphy.Real,
        collision_result: *const zphy.CollideShapeResult,
    ) callconv(.C) zphy.ValidateResult {
        _ = iself;
        _ = body1;
        _ = body2;
        _ = base_offset;
        _ = collision_result;
        return .accept_all_contacts;
    }

    fn _onContactAdded(
        iself: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        manifold: *const zphy.ContactManifold,
        settings: *zphy.ContactSettings,
    ) callconv(.C) void {
        const self = @as(*const ContactListener, @ptrCast(iself));
        const ent1 = body1.user_data;
        const ent2 = body2.user_data;

        self.ctx.state.frame_contacts.append(.{
            .body_id1 = body1.id,
            .body_id2 = body2.id,
            .ent1 = ent1,
            .ent2 = ent2,
            .manifold = manifold.*,
            .settings = settings.*,
        }) catch unreachable;
    }
};

const WorldLoaderData = struct {
    ent: ecs.entity_t = 0,
    pos_old: [3]f32 = .{ -100000, 0, -100000 },
};

const Patch = struct {
    body_opt: ?zphy.BodyId = null,
    shape_opt: ?*zphy.Shape = null,
    lookup: world_patch_manager.PatchLookup,
};

const IndexType = u32;

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    arena_system_update: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    event_mgr: *EventManager,
    physics_world: *zphy.PhysicsSystem,
    physics_world_low: *zphy.PhysicsSystem,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
};

const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_update: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    event_mgr: *EventManager,
    physics_world: *zphy.PhysicsSystem,
    physics_world_low: *zphy.PhysicsSystem,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    state: struct {
        contact_listener: *ContactListener = undefined,
        frame_contacts: std.ArrayList(config.events.CollisionContact) = undefined,
        loaders: [1]WorldLoaderData = .{.{}},
        requester_id: world_patch_manager.RequesterId = undefined,
        patches: std.ArrayList(Patch) = undefined,
        is_low: bool,
        // indices: [indices_per_patch]IndexType = undefined,
    },
};

pub fn create(create_ctx: SystemCreateCtx) void {
    const arena_system_lifetime = create_ctx.arena_system_lifetime;
    const heap_allocator = create_ctx.heap_allocator;
    const world_patch_mgr = create_ctx.world_patch_mgr;

    const broad_phase_layer_interface = arena_system_lifetime.create(BroadPhaseLayerInterface) catch unreachable;
    broad_phase_layer_interface.* = BroadPhaseLayerInterface.init();

    const object_vs_broad_phase_layer_filter = arena_system_lifetime.create(ObjectVsBroadPhaseLayerFilter) catch unreachable;
    object_vs_broad_phase_layer_filter.* = .{};

    const object_layer_pair_filter = arena_system_lifetime.create(ObjectLayerPairFilter) catch unreachable;
    object_layer_pair_filter.* = .{};

    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{
        .requester_id = world_patch_mgr.registerRequester(IdLocal.init("physics")),
        .patches = std.ArrayList(Patch).initCapacity(arena_system_lifetime, 16 * 16) catch unreachable,
        // .indices = undefined,
        .contact_listener = undefined,
        .frame_contacts = std.ArrayList(config.events.CollisionContact).initCapacity(arena_system_lifetime, 8192) catch unreachable,
        .is_low = false,
    };

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updatePhysicsWorld;
        system_desc.ctx = update_ctx;
        system_desc.ctx_free = destroy;
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updatePhysicsWorld",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateCollisions;
        system_desc.ctx = update_ctx;
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateCollisions",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateBodies;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.PhysicsBody), .inout = .In },
            .{ .id = ecs.id(fd.Position), .inout = .InOut },
            .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 3);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateBodies",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateLoaders;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.WorldLoader), .inout = .InOut },
            .{ .id = ecs.id(fd.Transform), .inout = .In },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateLoaders",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updatePatches;
        system_desc.ctx = update_ctx;
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updatePatches",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    const contact_listener = arena_system_lifetime.create(ContactListener) catch unreachable;
    contact_listener.* = .{ .ctx = update_ctx };
    create_ctx.physics_world.setContactListener(contact_listener);
    update_ctx.state.contact_listener = contact_listener;

    // Low physics
    const update_ctx_low = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx_low.* = SystemUpdateContext.view(create_ctx);
    update_ctx_low.*.state = .{
        .requester_id = world_patch_mgr.registerRequester(IdLocal.init("physics_low")),
        .patches = std.ArrayList(Patch).initCapacity(heap_allocator, 16 * 16) catch unreachable,
        .is_low = true,
    };

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updatePhysicsWorld;
        system_desc.ctx = update_ctx_low;
        system_desc.ctx_free = destroy;
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updatePhysicsWorldLow",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateLoaders;
        system_desc.ctx = update_ctx_low;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.WorldLoader), .inout = .InOut },
            .{ .id = ecs.id(fd.Transform), .inout = .In },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateLoadersLow",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updatePatches;
        system_desc.ctx = update_ctx_low;
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updatePatchesLow",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

pub fn destroy(ctx_opaque: ?*anyopaque) callconv(.C) void {
    const ctx: *SystemUpdateContext = @ptrCast(@alignCast(ctx_opaque));

    const query = ecs.query_init(ctx.ecsu_world.world, &.{
        .terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.PhysicsBody), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 1),
    }) catch unreachable;

    var query_iter = ecs.query_iter(ctx.ecsu_world.world, query);
    while (ecs.query_next(&query_iter)) {
        const bodies = ecs.field(&query_iter, fd.PhysicsBody, 0).?;
        for (bodies) |*body_comp| {
            if (body_comp.shape_opt) |shape| {
                shape.release();
                body_comp.shape_opt = null;
            }
        }
    }

    for (ctx.state.patches.items) |*patch| {
        if (patch.shape_opt) |shape| {
            shape.release();
            patch.shape_opt = null;
        }
    }
}

const physics_skip_frame_rate = 1;
var physics_skip_frame_counter: u32 = 1;
fn updatePhysicsWorld(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    physics_skip_frame_counter += 1;
    if (physics_skip_frame_counter % physics_skip_frame_rate == 0) {
        if (ctx.state.is_low) {
            _ = ctx.physics_world_low.update(it.delta_time, .{}) catch unreachable;
        } else {
            _ = ctx.physics_world.update(it.delta_time, .{}) catch unreachable;
        }
    }
}

fn updateCollisions(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    if (ctx.state.frame_contacts.items.len == 0) {
        return;
    }

    const frame_collisions_data = config.events.FrameCollisionsData{
        .contacts = ctx.state.frame_contacts.items,
    };
    ctx.event_mgr.triggerEvent(config.events.frame_collisions_id, &frame_collisions_data);
    ctx.state.frame_contacts.clearRetainingCapacity();
}

fn updateBodies(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const bodies = ecs.field(it, fd.PhysicsBody, 0).?;
    const positions = ecs.field(it, fd.Position, 1).?;
    const rotations = ecs.field(it, fd.Rotation, 2).?;

    const handedness_offset = std.math.pi;
    const up_world_z = zm.f32x4(0.0, 1.0, 0.0, 1.0);
    const jolt_rot_z = zm.quatFromAxisAngle(up_world_z, handedness_offset);
    const body_interface = ctx.physics_world.getBodyInterfaceMut();
    for (bodies, positions, rotations) |body, *pos, *rot| {
        const body_id = body.body_id;
        if (!body_interface.isAdded(body_id)) {
            continue;
        }

        // Pos
        const body_pos = body_interface.getPosition(body_id);
        pos.elems().* = body_pos;

        // Rot
        const body_rot_jolt = body_interface.getRotation(body_id);
        const body_rot_jolt_z = zm.loadArr4(body_rot_jolt);
        const body_rot_z = zm.qmul(jolt_rot_z, body_rot_jolt_z);
        rot.fromZM(body_rot_z);
    }
}

fn updateLoaders(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const world_loaders = ecs.field(it, fd.WorldLoader, 0).?;
    const transforms = ecs.field(it, fd.Transform, 1).?;

    const physics_world = if (ctx.state.is_low) ctx.physics_world_low else ctx.physics_world;
    const body_interface = physics_world.getBodyInterfaceMut();
    var arena_state = std.heap.ArenaAllocator.init(ctx.arena_system_update);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    for (world_loaders, transforms, it.entities()) |loader_comp, transform, ent| {
        if (!loader_comp.physics) {
            continue;
        }

        var loader = blk: {
            for (&ctx.state.loaders) |*loader| {
                if (loader.ent == ent) {
                    break :blk loader;
                }
            }

            // HACK
            ctx.state.loaders[0].ent = ent;
            break :blk &ctx.state.loaders[0];

            // unreachable;
        };

        const pos_new = transform.getPos00();
        const trigger_dist: f32 = if (ctx.state.is_low) 256 else 32;
        if (tides_math.dist3_xz(pos_new, loader.pos_old) < trigger_dist) {
            continue;
        }

        var lookups_old = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        var lookups_new = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;

        const area_width: f32 = if (ctx.state.is_low) (4 * 1024) else 512;
        const area_old = world_patch_manager.RequestRectangle{
            .x = loader.pos_old[0] - area_width / 2,
            .z = loader.pos_old[2] - area_width / 2,
            .width = area_width,
            .height = area_width,
        };

        const area_new = world_patch_manager.RequestRectangle{
            .x = pos_new[0] - area_width / 2,
            .z = pos_new[2] - area_width / 2,
            .width = area_width,
            .height = area_width,
        };

        const patch_lod: world_patch_manager.LoD = if (ctx.state.is_low) 3 else 0;
        const patch_type_id = ctx.world_patch_mgr.getPatchTypeId(IdLocal.init("heightmap"));
        world_patch_manager.WorldPatchManager.getLookupsFromRectangle(patch_type_id, area_old, patch_lod, &lookups_old);
        world_patch_manager.WorldPatchManager.getLookupsFromRectangle(patch_type_id, area_new, patch_lod, &lookups_new);

        var i_old: u32 = 0;
        blk: while (i_old < lookups_old.items.len) {
            var i_new: u32 = 0;
            while (i_new < lookups_new.items.len) {
                if (lookups_old.items[i_old].eql(lookups_new.items[i_new])) {
                    _ = lookups_old.swapRemove(i_old);
                    _ = lookups_new.swapRemove(i_new);
                    continue :blk;
                }
                i_new += 1;
            }
            i_old += 1;
        }

        // HACK
        if (loader.pos_old[0] != -100000) {
            ctx.world_patch_mgr.removeLoadRequestFromLookups(ctx.state.requester_id, lookups_old.items);

            for (lookups_old.items) |lookup| {
                for (ctx.state.patches.items, 0..) |*patch, i| {
                    if (patch.lookup.eql(lookup)) {
                        if (patch.body_opt != null) {
                            body_interface.removeAndDestroyBody(patch.body_opt.?);
                            patch.shape_opt.?.release();
                        }

                        _ = ctx.state.patches.swapRemove(i);
                        break;
                    }
                }
            }
        }

        ctx.world_patch_mgr.addLoadRequestFromLookups(ctx.state.requester_id, lookups_new.items, .high);

        for (lookups_new.items) |lookup| {
            ctx.state.patches.appendAssumeCapacity(.{
                .lookup = lookup,
            });
        }

        loader.pos_old = pos_new;
    }
}

fn updatePatches(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    for (ctx.state.patches.items) |*patch| {
        if (patch.body_opt) |body| {
            _ = body;
            continue;
        }

        const patch_info = ctx.world_patch_mgr.tryGetPatch(patch.lookup, patch_types.Heightmap);
        if (patch_info.data_opt) |data| {
            const world_pos = patch.lookup.getWorldPos();

            //  TODO: Use mesh (why though?)
            const height_field_size = config.patch_size;
            var samples: [height_field_size * height_field_size]f32 = undefined;

            const width = @as(u32, @intCast(config.patch_size));
            for (0..width) |z| {
                for (0..width) |x| {
                    const index = @as(u32, @intCast(x + z * config.patch_resolution));
                    const height = data.heightmap[index];
                    const sample = &samples[x + z * width];
                    sample.* = height;
                }
            }

            const scale: f32 = 65.0 / 64.0;
            var shape_settings = zphy.HeightFieldShapeSettings.create(&samples, height_field_size) catch unreachable;
            shape_settings.setScale(.{ scale, 1, scale });
            defer shape_settings.release();
            const shape = shape_settings.createShape() catch unreachable;

            const physics_world = if (ctx.state.is_low) ctx.physics_world_low else ctx.physics_world;
            const body_interface = physics_world.getBodyInterfaceMut();
            const body_id = body_interface.createAndAddBody(.{
                .position = .{ @as(f32, @floatFromInt(world_pos.world_x)), 0, @as(f32, @floatFromInt(world_pos.world_z)), 1.0 },
                .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
                .shape = shape,
                .motion_type = .static,
                .object_layer = object_layers.non_moving,
                .user_data = 0,
            }, .activate) catch unreachable;

            physics_world.optimizeBroadPhase();

            patch.shape_opt = shape;
            patch.body_opt = body_id;
        }
    }
}

//  ██████╗ █████╗ ██╗     ██╗     ██████╗  █████╗  ██████╗██╗  ██╗███████╗
// ██╔════╝██╔══██╗██║     ██║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝
// ██║     ███████║██║     ██║     ██████╔╝███████║██║     █████╔╝ ███████╗
// ██║     ██╔══██║██║     ██║     ██╔══██╗██╔══██║██║     ██╔═██╗ ╚════██║
// ╚██████╗██║  ██║███████╗███████╗██████╔╝██║  ██║╚██████╗██║  ██╗███████║
//  ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝
