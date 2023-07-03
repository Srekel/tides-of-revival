const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const zm = @import("zmath");
const zphy = @import("zphysics");

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
const config = @import("../config.zig");
const util = @import("../util.zig");
const EventManager = @import("../core/event_manager.zig").EventManager;

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
        .getBroadPhaseLayer = _getBroadPhaseLayer,
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
    system: *SystemState,

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
        self.system.frame_contacts.append(.{
            .body_id1 = body1.id,
            .body_id2 = body2.id,
            .ent1 = body1.user_data,
            .ent2 = body2.user_data,
            .manifold = manifold.*,
            .settings = settings.*,
        }) catch unreachable;
    }
};

const WorldLoaderData = struct {
    ent: flecs.EntityId = 0,
    pos_old: [3]f32 = .{ -100000, 0, -100000 },
};

const Patch = struct {
    body_opt: ?zphy.BodyId = null,
    shape_opt: ?*zphy.Shape = null,
    lookup: world_patch_manager.PatchLookup,
};

const IndexType = u32;

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    physics_world: *zphy.PhysicsSystem,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    event_manager: *EventManager,
    sys: flecs.EntityId,

    contact_listener: *ContactListener,
    frame_contacts: std.ArrayList(config.events.CollisionContact),
    comp_query_body: flecs.Query,
    comp_query_loader: flecs.Query,
    loaders: [1]WorldLoaderData = .{.{}},
    requester_id: world_patch_manager.RequesterId,
    patches: std.ArrayList(Patch),
    indices: [indices_per_patch]IndexType,
};

pub fn create(name: IdLocal, ctx: util.Context) !*SystemState {
    const allocator = ctx.getConst(config.allocator.hash, std.mem.Allocator).*;
    const flecs_world = ctx.get(config.flecs_world.hash, flecs.World);
    const event_manager = ctx.get(config.event_manager.hash, EventManager);
    const world_patch_mgr = ctx.get(config.world_patch_mgr.hash, world_patch_manager.WorldPatchManager);

    var query_builder_body = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_body.with(fd.PhysicsBody)
        .with(fd.Position)
        .with(fd.EulerRotation);
    // .with(fd.Transform);
    const comp_query_body = query_builder_body.buildQuery();

    var query_builder_loader = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_loader.with(fd.WorldLoader)
        .with(fd.Transform);
    const comp_query_loader = query_builder_loader.buildQuery();

    const broad_phase_layer_interface = allocator.create(BroadPhaseLayerInterface) catch unreachable;
    broad_phase_layer_interface.* = BroadPhaseLayerInterface.init();

    const object_vs_broad_phase_layer_filter = allocator.create(ObjectVsBroadPhaseLayerFilter) catch unreachable;
    object_vs_broad_phase_layer_filter.* = .{};

    const object_layer_pair_filter = allocator.create(ObjectLayerPairFilter) catch unreachable;
    object_layer_pair_filter.* = .{};

    zphy.init(allocator, .{}) catch unreachable;
    const physics_world = zphy.PhysicsSystem.create(
        @as(*const zphy.BroadPhaseLayerInterface, @ptrCast(broad_phase_layer_interface)),
        @as(*const zphy.ObjectVsBroadPhaseLayerFilter, @ptrCast(object_vs_broad_phase_layer_filter)),
        @as(*const zphy.ObjectLayerPairFilter, @ptrCast(object_layer_pair_filter)),
        .{
            .max_bodies = 1024,
            .num_body_mutexes = 0,
            .max_body_pairs = 1024,
            .max_contact_constraints = 1024,
        },
    ) catch unreachable;

    physics_world.setGravity(.{ 0, -10.0, 0 });

    var system = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .physics_world = physics_world,
        .world_patch_mgr = world_patch_mgr,
        .sys = sys,
        .comp_query_body = comp_query_body,
        .comp_query_loader = comp_query_loader,
        .requester_id = world_patch_mgr.registerRequester(IdLocal.init("physics")),
        .patches = std.ArrayList(Patch).initCapacity(allocator, 8 * 8) catch unreachable,
        .indices = undefined,
        .contact_listener = undefined,
        .frame_contacts = std.ArrayList(config.events.CollisionContact).initCapacity(allocator, 8192) catch unreachable,
        .event_manager = event_manager,
    };

    const contact_listener = allocator.create(ContactListener) catch unreachable;
    contact_listener.* = .{
        .system = system,
    };
    physics_world.setContactListener(contact_listener);
    system.contact_listener = contact_listener;
    // flecs_world.observer(ObserverCallback, .on_set, system);

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.comp_query_body.deinit();
    system.comp_query_loader.deinit();
    system.physics_world.destroy();
    zphy.deinit();
    system.patches.deinit();
    system.frame_contacts.deinit();
    system.allocator.destroy(system.contact_listener);
    system.allocator.destroy(system);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    // system.physics_world.optimizeBroadPhase();
    _ = system.physics_world.update(iter.iter.delta_time, .{}) catch unreachable;
    updateCollisions(system);
    updateBodies(system);
    updateLoaders(system);
    updatePatches(system);
}

fn updateCollisions(system: *SystemState) void {
    if (system.frame_contacts.items.len == 0) {
        return;
    }

    const frame_collisions_data = config.events.FrameCollisionsData{
        .contacts = system.frame_contacts.items,
    };
    system.event_manager.triggerEvent(config.events.frame_collisions_id, &frame_collisions_data);
    system.frame_contacts.clearRetainingCapacity();

    // const flecs_world = system.flecs_world;
    // var id_list = [_]flecs.c.EcsId{
    //     flecs.meta.componentId(flecs_world.world, fd.PhysicsBody),
    // };
    // const ids = flecs.c.EcsType{
    //     .array = id_list[0..].ptr,
    //     .count = 1,
    // };

    // var param = config.events.OnCollisionContext{
    //     .contacts = system.frame_contacts.items,
    // };

    // var desc: flecs.c.EcsEventDesc = .{
    //     .event = config.events.onCollisionId(flecs_world.world),
    //     .ids = &ids,
    //     .param = &param, // list of collisions since previous frame
    //     .table = null,
    //     .other_table = null,
    //     .offset = 0,
    //     .count = 0,
    //     .entity = system.sys,
    //     .observable = null,
    //     .flags = 0,
    // };

    // flecs.ecs_emit(flecs_world.world, &desc);
    // system.frame_contacts.clearRetainingCapacity();

    // for (system.frame_contacts.items) |*contact| {
    //     // _ = flecs_world;
    //     // const ent1 = flecs.Entity.init(flecs_world.world, body1.user_data);
    //     // const ent2 = flecs.Entity.init(flecs_world.world, body2.user_data);

    //     // const context = config.events.OnCollisionContext{};
    //     // _ = context;
    //     // var desc: flecs.c.EcsEventDesc = .{
    //     //     // .event = config.event.OnCollision,
    //     //     .event = config.events.onCollisionId(flecs_world.world),
    //     //     .ids = &ids,
    //     //     .param = contact,
    //     //     .table = null,
    //     //     .other_table = null,
    //     //     .offset = 0,
    //     //     .count = 0,
    //     //     .entity = 0,
    //     //     .observable = null,
    //     //     .flags = 0,
    //     // };

    //     // flecs.ecs_emit(flecs_world.world, &desc);
    // }
}

fn updateBodies(system: *SystemState) void {
    var entity_iter = system.comp_query_body.iterator(struct {
        body: *fd.PhysicsBody,
        pos: *fd.Position,
        rot: *fd.EulerRotation,
        // transform: *fd.Transform,
    });

    const body_interface = system.physics_world.getBodyInterfaceMut();
    while (entity_iter.next()) |comps| {
        var body_comp = comps.body;
        var body_id = body_comp.body_id;

        if (!body_interface.isAdded(body_id)) {
            continue;
        }

        // Pos
        const body_pos = body_interface.getPosition(body_id);
        comps.pos.elems().* = body_pos;

        // Rot
        const body_rot = body_interface.getRotation(body_id);
        const body_rot_z = zm.loadArr4(body_rot);
        const body_rot_rpy = zm.quatToRollPitchYaw([_]f32{ body_rot_z[0], body_rot_z[1], body_rot_z[2], body_rot_z[3] });

        comps.rot.roll = body_rot_rpy[2];
        comps.rot.pitch = body_rot_rpy[0];
        comps.rot.yaw = body_rot_rpy[1];
    }
}

fn updateLoaders(system: *SystemState) void {
    var entity_iter = system.comp_query_loader.iterator(struct {
        WorldLoader: *fd.WorldLoader,
        transform: *fd.Transform,
    });

    const body_interface = system.physics_world.getBodyInterfaceMut();
    var arena_state = std.heap.ArenaAllocator.init(system.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    while (entity_iter.next()) |comps| {
        var loader_comp = comps.WorldLoader;
        if (!loader_comp.physics) {
            continue;
        }

        var loader = blk: {
            for (&system.loaders) |*loader| {
                if (loader.ent == entity_iter.entity().id) {
                    break :blk loader;
                }
            }

            // HACK
            system.loaders[0].ent = entity_iter.entity().id;
            break :blk &system.loaders[0];

            // unreachable;
        };

        const pos_new = comps.transform.getPos00();
        if (tides_math.dist3_xz(pos_new, loader.pos_old) < 32) {
            continue;
        }

        var lookups_old = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        var lookups_new = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;

        const area_old = world_patch_manager.RequestRectangle{
            .x = loader.pos_old[0] - 64,
            .z = loader.pos_old[2] - 64,
            .width = 128,
            .height = 128,
        };

        const area_new = world_patch_manager.RequestRectangle{
            .x = pos_new[0] - 64,
            .z = pos_new[2] - 64,
            .width = 128,
            .height = 128,
        };

        const patch_type_id = system.world_patch_mgr.getPatchTypeId(IdLocal.init("heightmap"));
        world_patch_manager.WorldPatchManager.getLookupsFromRectangle(patch_type_id, area_old, 0, &lookups_old);
        world_patch_manager.WorldPatchManager.getLookupsFromRectangle(patch_type_id, area_new, 0, &lookups_new);

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
            system.world_patch_mgr.removeLoadRequestFromLookups(system.requester_id, lookups_old.items);

            for (lookups_old.items) |lookup| {
                for (system.patches.items, 0..) |*patch, i| {
                    if (patch.lookup.eql(lookup)) {
                        body_interface.removeAndDestroyBody(patch.body_opt.?);
                        patch.shape_opt.?.release();

                        _ = system.patches.swapRemove(i);
                        break;
                    }
                }
            }
        }

        system.world_patch_mgr.addLoadRequestFromLookups(system.requester_id, lookups_new.items, .high);

        for (lookups_new.items) |lookup| {
            system.patches.appendAssumeCapacity(.{
                .lookup = lookup,
            });
        }

        loader.pos_old = pos_new;
    }
}

fn updatePatches(system: *SystemState) void {
    for (system.patches.items) |*patch| {
        if (patch.body_opt) |body| {
            _ = body;
            continue;
        }

        const patch_info = system.world_patch_mgr.tryGetPatch(patch.lookup, f32);
        if (patch_info.data_opt) |data| {
            // _ = data;

            const world_pos = patch.lookup.getWorldPos();
            // var vertices: [config.patch_resolution * config.patch_resolution][3]f32 = undefined;
            // var z: u32 = 0;
            // while (z < config.patch_resolution) : (z += 1) {
            //     var x: u32 = 0;
            //     while (x < config.patch_resolution) : (x += 1) {
            //         const index = @intCast(u32, x + z * config.patch_resolution);
            //         const height = data[index];

            //         vertices[index][0] = @floatFromInt(f32, x);
            //         vertices[index][1] = height;
            //         vertices[index][2] = @floatFromInt(f32, z);
            //     }
            // }

            // var indices = &system.indices;
            // // var indices: [indices_per_patch]IndexType = undefined;

            // // TODO: Optimize, don't do it for every frame!
            // var i: u32 = 0;
            // z = 0;
            // const width = @intCast(u32, config.patch_resolution);
            // const height = @intCast(u32, config.patch_resolution);
            // while (z < height - 1) : (z += 1) {
            //     var x: u32 = 0;
            //     while (x < width - 1) : (x += 1) {
            //         const indices_quad = [_]u32{
            //             x + z * width, //           0
            //             x + (z + 1) * width, //     4
            //             x + 1 + z * width, //       1
            //             x + 1 + (z + 1) * width, // 5
            //         };

            //         indices[i + 0] = indices_quad[0]; // 0
            //         indices[i + 1] = indices_quad[1]; // 4
            //         indices[i + 2] = indices_quad[2]; // 1

            //         indices[i + 3] = indices_quad[2]; // 1
            //         indices[i + 4] = indices_quad[1]; // 4
            //         indices[i + 5] = indices_quad[3]; // 5

            //         // std.debug.print("quad: {any}\n", .{indices_quad});
            //         // std.debug.print("indices: {any}\n", .{patch_indices[i .. i + 6]});
            //         // std.debug.print("tri: {any} {any} {any}\n", .{
            //         //     patch_vertex_positions[patch_indices[i + 0]],
            //         //     patch_vertex_positions[patch_indices[i + 1]],
            //         //     patch_vertex_positions[patch_indices[i + 2]],
            //         // });
            //         // std.debug.print("tri: {any} {any} {any}\n", .{
            //         //     patch_vertex_positions[patch_indices[i + 3]],
            //         //     patch_vertex_positions[patch_indices[i + 4]],
            //         //     patch_vertex_positions[patch_indices[i + 5]],
            //         // });
            //         i += 6;
            //     }
            // }
            // std.debug.assert(i == indices_per_patch);
            // std.debug.assert(i == indices_per_patch);
            // std.debug.assert(i == indices_per_patch);
            // std.debug.assert(i == indices_per_patch);

            // std.debug.assert(patch_indices.len == indices_per_patch);

            //  TODO: Use heightfield...?
            const height_field_size = config.patch_size;
            var samples: [height_field_size * height_field_size]f32 = undefined;

            const width = @as(u32, @intCast(config.patch_size));
            for (0..width) |z| {
                for (0..width) |x| {
                    const index = @as(u32, @intCast(x + z * config.patch_resolution));
                    const height = data[index];
                    var sample = &samples[x + z * width];
                    sample.* = height;
                    // sample.* = data[0] + @floatFromInt(f32, x + z) * 0.1;
                }
            }
            // while (z < height - 1) : (z += 1) {
            //     var x: u32 = 0;
            //     while (x < width - 1) : (x += 1) {}
            // }

            const shape_settings = zphy.HeightFieldShapeSettings.create(&samples, height_field_size) catch unreachable;
            defer shape_settings.release();
            const shape = shape_settings.createShape() catch unreachable;

            const body_interface = system.physics_world.getBodyInterfaceMut();
            const body_id = body_interface.createAndAddBody(.{
                .position = .{ @as(f32, @floatFromInt(world_pos.world_x)), 0, @as(f32, @floatFromInt(world_pos.world_z)), 1.0 },
                .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
                .shape = shape,
                .motion_type = .static,
                .object_layer = object_layers.non_moving,
                .user_data = 0,
            }, .activate) catch unreachable;

            system.physics_world.optimizeBroadPhase();

            // const query = system.physics_world.getNarrowPhaseQuery();
            // for (0..width) |z| {
            //     for (0..width) |x| {
            //         const ray_origin = [_]f32{
            //             @floatFromInt(f32, world_pos.world_x + x),
            //             1000,
            //             @floatFromInt(f32, world_pos.world_z + z),
            //             0,
            //         };
            //         const ray_dir = [_]f32{ 0, -1000, 0, 0 };
            //         var result = query.castRay(.{
            //             .origin = ray_origin,
            //             .direction = ray_dir,
            //         }, .{});

            //         if (result.has_hit) {
            //             const post_pos = fd.Position.init(
            //                 ray_origin[0] + ray_dir[0] * result.hit.fraction,
            //                 ray_origin[1] + ray_dir[1] * result.hit.fraction,
            //                 ray_origin[2] + ray_dir[2] * result.hit.fraction,
            //             );
            //             _ = post_pos;
            //             const post_pos2 = fd.Position.init(
            //                 @floatFromInt(f32, world_pos.world_x + x),
            //                 data[x + z * config.patch_resolution],
            //                 @floatFromInt(f32, world_pos.world_z + z),
            //             );
            //             var post_transform = fd.Transform.initFromPosition(post_pos2);
            //             post_transform.setScale([_]f32{ 0.2, 0.2, 0.2 });

            //             const post_ent = system.flecs_world.newEntity();
            //             post_ent.set(post_pos2);
            //             post_ent.set(fd.EulerRotation{});
            //             post_ent.set(fd.Scale.create(0.2, 0.2, 0.2));
            //             post_ent.set(post_transform);
            //             post_ent.set(fd.CIShapeMeshInstance{
            //                 .id = IdLocal.id64("cylinder"),
            //                 .basecolor_roughness = .{ .r = 1.0, .g = 1.0, .b = 0.0, .roughness = 0.8 },
            //             });
            //         }
            //     }
            // }
            // const trimesh = zbt.initTriangleMeshShape();
            // trimesh.addIndexVertexArray(
            //     @intCast(u32, indices_per_patch / 3),
            //     &system.indices,
            //     @sizeOf([3]u32),
            //     @intCast(u32, vertices[0..].len),
            //     &vertices[0],
            //     @sizeOf([3]f32),
            // );
            // trimesh.finish();

            // const shape = trimesh.asShape();
            patch.shape_opt = shape;

            // const transform = [_]f32{
            //     1.0,                                 0.0, 0.0,
            //     0.0,                                 1.0, 0.0,
            //     0.0,                                 0.0, 1.0,
            //     @floatFromInt(f32, world_pos.world_x), 0,   @floatFromInt(f32, world_pos.world_z),
            // };

            // const body = zbt.initBody(
            //     0,
            //     &transform,
            //     patch.shape_opt.?,
            // );

            // body.setDamping(0.1, 0.1);
            // body.setRestitution(0.5);
            // body.setFriction(0.2);
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

// const ObserverCallback = struct {
//     body: *const fd.CIPhysicsBody,

//     pub const name = "CIPhysicsBody";
//     pub const run = onSetCIPhysicsBody;
// };

// fn onSetCIPhysicsBody(it: *flecs.Iterator(ObserverCallback)) void {
//     var observer = @ptrCast(*flecs.c.ecs_observer_t, @alignCast(@alignOf(flecs.c.ecs_observer_t), it.iter.ctx));
//     var system : *SystemState = @ptrCast(@alignCast(observer.*.ctx));
//     _ = system;
//     // while (it.next()) |_| {
//     //     const ci_ptr = flecs.c.ecs_field_w_size(it.iter, @sizeOf(fd.CIPhysicsBody), @intCast(i32, it.index)).?;
//     //     var ci = @ptrCast(*fd.CIPhysicsBody, @alignCast(@alignOf(fd.CIPhysicsBody), ci_ptr));

//     //     var transform = it.entity().getMut(fd.Transform).?;
//     //     const shape = switch (ci.shape_type) {
//     //         .box => zbt.initBoxShape(&.{ ci.box.size, ci.box.size, ci.box.size }).asShape(),
//     //         .sphere => zbt.initSphereShape(ci.sphere.radius).asShape(),
//     //     };
//     //     const body = zbt.initBody(
//     //         ci.mass,
//     //         &transform.matrix,
//     //         shape,
//     //     );

//     //     body.setDamping(0.1, 0.1);
//     //     body.setRestitution(0.5);
//     //     body.setFriction(0.2);

//     //     system.physics_world.addBody(body);

//     //     const ent = it.entity();
//     //     ent.remove(fd.CIPhysicsBody);
//     //     ent.set(fd.PhysicsBody{
//     //         .body = body,
//     //     });
//     // }
// }
