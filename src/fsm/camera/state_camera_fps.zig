const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../core/blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const fd = @import("../../config/flecs_data.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config/config.zig");
const zphy = @import("zphysics");
const PrefabManager = @import("../../prefab_manager.zig").PrefabManager;
const util = @import("../../util.zig");
const context = @import("../../core/context.zig");

pub const StateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
};

pub fn create(create_ctx: StateContext) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(StateContext) catch unreachable;
    update_ctx.* = StateContext.view(create_ctx);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = cameraStateFps;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Input), .inout = .InOut },
            .{ .id = ecs.id(fd.Camera), .inout = .InOut },
            .{ .id = ecs.id(fd.Transform), .inout = .InOut },
            .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
            .{ .id = ecs.pair(fd.FSM_CAM, fd.FSM_CAM_Fps), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 5);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "cameraStateFps",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

fn cameraStateFps(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const inputs = ecs.field(it, fd.Input, 0).?;
    const cameras = ecs.field(it, fd.Camera, 1).?;
    const transforms = ecs.field(it, fd.Transform, 2).?;
    const rotations = ecs.field(it, fd.Rotation, 3).?;

    const movement_pitch = ctx.input_frame_data.get(config.input.look_pitch).number;
    for (inputs, cameras, transforms, rotations) |input_comp, cam, transform, *rot| {
        _ = transform; // autofix
        _ = input_comp; // autofix
        if (!cam.active) {
            continue;
        }

        const rot_pitch = zm.quatFromNormAxisAngle(zm.Vec{ 1, 0, 0, 0 }, movement_pitch * 0.0025);
        const rot_in = rot.asZM();
        const rot_new = zm.qmul(rot_in, rot_pitch);
        rot.fromZM(rot_new);

        const rpy = zm.quatToRollPitchYaw(rot_new);
        const rpy_constrained = .{
            std.math.clamp(rpy[0], -0.9, 0.9),
            rpy[1],
            rpy[2],
        };
        const constrained_z = zm.quatFromRollPitchYaw(rpy_constrained[0], rpy_constrained[1], rpy_constrained[2]);
        rot.fromZM(constrained_z);
    }
}

// fn updateInteract(transform: *fd.Transform, physics_world: *zphy.PhysicsSystem, ecsu_world: ecsu.World, input_state: *const input.FrameData, prefab_mgr: *PrefabManager) void {
//     // TODO: No, interaction shouldn't be in camera.. :)
//     if (!input_state.just_pressed(config.input.interact)) {
//         return;
//     }

//     const z_mat = zm.loadMat43(transform.matrix[0..]);
//     const z_pos = zm.util.getTranslationVec(z_mat);
//     const z_fwd = zm.util.getAxisZ(z_mat);

//     const query = physics_world.getNarrowPhaseQuery();
//     const ray_origin = [_]f32{ z_pos[0], z_pos[1], z_pos[2], 0 };
//     const ray_dir = [_]f32{ z_fwd[0] * 50, z_fwd[1] * 50, z_fwd[2] * 50, 0 };
//     const result = query.castRay(.{
//         .origin = ray_origin,
//         .direction = ray_dir,
//     }, .{});

//     if (result.has_hit) {
//         const post_pos = fd.Position.init(
//             ray_origin[0] + ray_dir[0] * result.hit.fraction,
//             ray_origin[1] + ray_dir[1] * result.hit.fraction,
//             ray_origin[2] + ray_dir[2] * result.hit.fraction,
//         );
//         var post_transform = fd.Transform.initFromPosition(post_pos);
//         post_transform.setScale([_]f32{ 0.05, 2, 0.05 });

//         const cylinder_prefab = prefab_mgr.getPrefab(config.prefab.cylinder_id).?;
//         const post_ent = prefab_mgr.instantiatePrefab(ecsu_world, cylinder_prefab);
//         post_ent.set(post_pos);
//         post_ent.set(fd.Rotation{});
//         post_ent.set(fd.Scale.create(0.05, 2, 0.05));
//         post_ent.set(post_transform);

//         // const light_pos = fd.Position.init(0.0, 1.0, 0.0);
//         // const light_transform = fd.Transform.init(post_pos.x, post_pos.y + 2.0, post_pos.z);
//         // const light_ent = ecsu_world.newEntity();
//         // light_ent.childOf(post_ent);
//         // light_ent.set(light_pos);
//         // light_ent.set(light_transform);
//         // light_ent.set(fd.Light{ .radiance = .{ .r = 1, .g = 0.4, .b = 0.0 }, .range = 20 });
//     }
// }
