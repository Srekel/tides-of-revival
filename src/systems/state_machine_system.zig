const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zm = @import("zmath");
const zphy = @import("zphysics");
const ztracy = @import("ztracy");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const fsm = @import("../fsm/fsm.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const BlobArray = @import("../core/blob_array.zig").BlobArray;
const input = @import("../input.zig");
const util = @import("../util.zig");
const PrefabManager = @import("../prefab_manager.zig").PrefabManager;
const config = @import("../config/config.zig");
const audio_manager = @import("../audio/audio_manager_mock.zig");
const context = @import("../core/context.zig");

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    audio_mgr: *audio_manager.AudioManager,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
};

const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    heap_allocator: std.mem.Allocator,
    audio_mgr: *audio_manager.AudioManager,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
    state: struct {
        state_machines: std.ArrayList(fsm.StateMachine),
        instances: std.ArrayList(StateMachineInstance),
    },
};

// const StateCameraFreefly = @import("../fsm/camera/state_camera_freefly.zig");
const StateCameraFPS = @import("../fsm/camera/state_camera_fps.zig");
// const StatePlayerIdle = @import("../fsm/player_controller/state_player_idle.zig");
// const StateGiantAnt = @import("../fsm/creature/state_giant_ant.zig");

const StateMachineInstance = struct {
    state_machine: *const fsm.StateMachine,
    curr_states: std.ArrayList(*fsm.State),
    entities: std.ArrayList(ecs.entity_t),
    blob_array: BlobArray(16),
};

pub fn create(create_ctx: SystemCreateCtx) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{
        .state_machines = std.ArrayList(fsm.StateMachine).init(create_ctx.heap_allocator),
        .instances = std.ArrayList(StateMachineInstance).init(create_ctx.heap_allocator),
    };

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateStateMachineSystem;
        system_desc.ctx = update_ctx;
        system_desc.ctx_free = destroy;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.FSM), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 1);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateStateMachineSystem",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    _ = ecs.observer_init(create_ctx.ecsu_world.world, &.{
        .callback = onSetCIFSM,
        .ctx = update_ctx,
        .query = .{
            .terms = [_]ecs.term_t{.{ .id = ecs.id(fd.CIFSM) }} ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 1),
        },
        .events = ([_]ecs.entity_t{ecs.OnSet} ++ .{0} ** (ecs.FLECS_EVENT_DESC_MAX - 1)),
    });

    initStateData(update_ctx);
}

pub fn destroy(ctx: ?*anyopaque) callconv(.C) void {
    const system: *SystemUpdateContext = @ptrCast(@alignCast(ctx));
    for (system.state.instances.items) |*item| {
        for (item.curr_states.items) |item2| {
            // item2.destroy(); // autofix
            // system.heap_allocator.destroy();
            system.heap_allocator.free(item2.self);
        }
        item.curr_states.deinit();
        item.entities.deinit();
        item.blob_array.destroy();
    }
    for (system.state.state_machines.items) |*item| {
        item.states.deinit();
    }
    system.state.instances.deinit();
    system.state.state_machines.deinit();
}

fn initStateData(system: *SystemUpdateContext) void {
    const sm_ctx = fsm.StateCreateContext.view(system);

    // const player_sm = blk: {
    //     const initial_state = StatePlayerIdle.create(sm_ctx);
    //     var states = std.ArrayList(fsm.State).init(system.heap_allocator);
    //     states.append(initial_state) catch unreachable;
    //     const sm = fsm.StateMachine.create("player_controller", states, "idle");
    //     system.state.state_machines.append(sm) catch unreachable;
    //     break :blk &system.state.state_machines.items[system.state.state_machines.items.len - 1];
    // };

    // system.state.instances.append(.{
    //     .state_machine = player_sm,
    //     .curr_states = std.ArrayList(*fsm.State).init(system.heap_allocator),
    //     .entities = std.ArrayList(ecs.entity_t).init(system.heap_allocator),
    //     .blob_array = blk: {
    //         const blob_array = BlobArray(16).create(system.heap_allocator, player_sm.max_state_size);
    //         break :blk blob_array;
    //     },
    // }) catch unreachable;

    // const debug_camera_sm = blk: {
    //     const initial_state = StateCameraFreefly.create(sm_ctx);
    //     var states = std.ArrayList(fsm.State).init(system.heap_allocator);
    //     states.append(initial_state) catch unreachable;
    //     const sm = fsm.StateMachine.create("debug_camera", states, "freefly");
    //     system.state.state_machines.append(sm) catch unreachable;
    //     break :blk &system.state.state_machines.items[system.state.state_machines.items.len - 1];
    // };

    // system.state.instances.append(.{
    //     .state_machine = debug_camera_sm,
    //     .curr_states = std.ArrayList(*fsm.State).init(system.heap_allocator),
    //     .entities = std.ArrayList(ecs.entity_t).init(system.heap_allocator),
    //     .blob_array = blk: {
    //         const blob_array = BlobArray(16).create(system.heap_allocator, debug_camera_sm.max_state_size);
    //         break :blk blob_array;
    //     },
    // }) catch unreachable;

    const fps_camera_sm = blk: {
        const initial_state = StateCameraFPS.create(sm_ctx);
        var states = std.ArrayList(fsm.State).init(system.heap_allocator);
        states.append(initial_state) catch unreachable;
        const sm = fsm.StateMachine.create("fps_camera", states, "fps_camera");
        system.state.state_machines.append(sm) catch unreachable;
        break :blk &system.state.state_machines.items[system.state.state_machines.items.len - 1];
    };

    system.state.instances.append(.{
        .state_machine = fps_camera_sm,
        .curr_states = std.ArrayList(*fsm.State).init(system.heap_allocator),
        .entities = std.ArrayList(ecs.entity_t).init(system.heap_allocator),
        .blob_array = blk: {
            const blob_array = BlobArray(16).create(system.heap_allocator, fps_camera_sm.max_state_size);
            break :blk blob_array;
        },
    }) catch unreachable;

    // const giant_ant_sm = blk: {
    //     const initial_state = StateGiantAnt.create(sm_ctx);
    //     var states = std.ArrayList(fsm.State).init(system.heap_allocator);
    //     states.append(initial_state) catch unreachable;
    //     const sm = fsm.StateMachine.create("giant_ant", states, "giant_ant");
    //     system.state.state_machines.append(sm) catch unreachable;
    //     break :blk &system.state.state_machines.items[system.state.state_machines.items.len - 1];
    // };

    // system.state.instances.append(.{
    //     .state_machine = giant_ant_sm,
    //     .curr_states = std.ArrayList(*fsm.State).init(system.heap_allocator),
    //     .entities = std.ArrayList(ecs.entity_t).init(system.heap_allocator),
    //     .blob_array = blk: {
    //         const blob_array = BlobArray(16).create(system.heap_allocator, giant_ant_sm.max_state_size);
    //         break :blk blob_array;
    //     },
    // }) catch unreachable;
}

fn updateStateMachineSystem(it: *ecs.iter_t) callconv(.C) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "State Machine System: Update", 0x00_ff_00_ff);
    defer trazy_zone.End();

    // defer ecs.iter_fini(iter.iter);
    const system: *SystemUpdateContext = @ptrCast(@alignCast(it.ctx));
    const dt4 = zm.f32x4s(it.delta_time);

    // var entity_iter = system.query.iterator(struct {
    //     fsm: *fd.FSM,
    // });

    // while (entity_iter.next()) |comps| {
    //     _ = comps;
    // }

    // const NextState = struct {
    //     entity: ecs.entity_t,
    //     next_state: *fsm.State,
    // };

    for (system.state.instances.items) |*instance| {
        for (instance.curr_states.items) |fsm_state| {
            const ctx = fsm.StateFuncContext{
                .state = fsm_state,
                .blob_array = &instance.blob_array,
                .heap_allocator = system.heap_allocator,
                .input_frame_data = system.input_frame_data,
                // .entity = instance.entities.items[i],
                // .data = instance.blob_array.getBlob(i),
                .transition_events = .{},
                .ecsu_world = system.ecsu_world,
                .physics_world = system.physics_world,
                .audio_mgr = system.audio_mgr,
                .dt = dt4,
            };
            fsm_state.update(ctx);
        }
    }
}

const ObserverCallback = struct {
    comp: *const fd.CIFSM,

    pub const name = "CIFSM";
    pub const run = onSetCIFSM;
};

fn onSetCIFSM(it: *ecs.iter_t) callconv(.C) void {
    const system: *SystemUpdateContext = @ptrCast(@alignCast(it.ctx));
    const cis = ecs.field(it, fd.CIFSM, 0).?;
    for (cis, 0..) |ci, i_ent| {
        // const ci_ptr = ecs.field_w_size(it.iter, @sizeOf(fd.CIFSM), @as(i32, @intCast(it.index))).?;
        // const ci = @as(*fd.CIFSM, @ptrCast(@alignCast(ci_ptr)));

        const smi_i = blk_smi_i: {
            const state_machine = blk_sm: {
                for (system.state.state_machines.items) |*sm| {
                    if (sm.name.eqlHash(ci.state_machine_hash)) {
                        break :blk_sm sm;
                    }
                }
                unreachable;
            };

            for (system.state.instances.items, 0..) |*smi, i| {
                if (smi.state_machine == state_machine) {
                    break :blk_smi_i .{
                        .smi = smi,
                        .index = i,
                    };
                }
            }
            unreachable;
        };

        const state_machine_instance = smi_i.smi;
        const ent = ecsu.Entity.init(it.world, it.entities()[i_ent]);
        state_machine_instance.entities.append(ent.id) catch unreachable;
        if (state_machine_instance.curr_states.items.len == 0) {
            state_machine_instance.curr_states.append(state_machine_instance.state_machine.initial_state) catch unreachable;
        }
        const blob_lookup = state_machine_instance.blob_array.addBlob();

        ent.remove(fd.CIFSM);
        ent.set(fd.FSM{
            .state_machine_lookup = @as(u16, @intCast(smi_i.index)),
            .blob_lookup = blob_lookup,
        });
        ent.set(fd.Forward{ .x = 0, .y = 0, .z = 1 });
    }
}
