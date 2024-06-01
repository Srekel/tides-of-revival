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
const context = @import("../core/context.zig");
const audio_manager = @import("../audio/audio_manager_mock.zig");

const StateCameraFreefly = @import("../fsm/camera/state_camera_freefly.zig");
const StateCameraFPS = @import("../fsm/camera/state_camera_fps.zig");
const StatePlayerIdle = @import("../fsm/player_controller/state_player_idle.zig");
const StateGiantAnt = @import("../fsm/creature/state_giant_ant.zig");

const StateMachineInstance = struct {
    state_machine: *const fsm.StateMachine,
    curr_states: std.ArrayList(*fsm.State),
    entities: std.ArrayList(ecs.entity_t),
    blob_array: BlobArray(16),
};

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    flecs_sys: ecs.entity_t,
    query: ecsu.Query,
    state_machines: std.ArrayList(fsm.StateMachine),
    instances: std.ArrayList(StateMachineInstance),
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
    audio_mgr: *audio_manager.AudioManager,
};

pub const SystemCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    audio_mgr: *audio_manager.AudioManager,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
};

pub fn create(
    name: IdLocal,
    allocator: std.mem.Allocator,
    ctx: SystemCtx,
) !*SystemState {
    var query_builder = ecsu.QueryBuilder.init(ctx.ecsu_world);
    _ = query_builder
        .with(fd.FSM);
    const query = query_builder.buildQuery();

    const system = allocator.create(SystemState) catch unreachable;
    const flecs_sys = ctx.ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .allocator = allocator,
        .ecsu_world = ctx.ecsu_world,
        .flecs_sys = flecs_sys,
        .query = query,
        .state_machines = std.ArrayList(fsm.StateMachine).init(allocator),
        .instances = std.ArrayList(StateMachineInstance).init(allocator),
        .input_frame_data = ctx.input_frame_data,
        .physics_world = ctx.physics_world,
        .audio_mgr = ctx.audio_mgr,
    };

    ctx.ecsu_world.observer(ObserverCallback, ecs.OnSet, system);

    initStateData(system);
    return system;
}

pub fn destroy(system: *SystemState) void {
    system.query.deinit();
    system.allocator.destroy(system);
}

fn initStateData(system: *SystemState) void {
    const sm_ctx = fsm.StateCreateContext.view(system);

    const player_sm = blk: {
        const initial_state = StatePlayerIdle.create(sm_ctx);
        var states = std.ArrayList(fsm.State).init(system.allocator);
        states.append(initial_state) catch unreachable;
        const sm = fsm.StateMachine.create("player_controller", states, "idle");
        system.state_machines.append(sm) catch unreachable;
        break :blk &system.state_machines.items[system.state_machines.items.len - 1];
    };

    system.instances.append(.{
        .state_machine = player_sm,
        .curr_states = std.ArrayList(*fsm.State).init(system.allocator),
        .entities = std.ArrayList(ecs.entity_t).init(system.allocator),
        .blob_array = blk: {
            const blob_array = BlobArray(16).create(system.allocator, player_sm.max_state_size);
            break :blk blob_array;
        },
    }) catch unreachable;

    const debug_camera_sm = blk: {
        const initial_state = StateCameraFreefly.create(sm_ctx);
        var states = std.ArrayList(fsm.State).init(system.allocator);
        states.append(initial_state) catch unreachable;
        const sm = fsm.StateMachine.create("debug_camera", states, "freefly");
        system.state_machines.append(sm) catch unreachable;
        break :blk &system.state_machines.items[system.state_machines.items.len - 1];
    };

    system.instances.append(.{
        .state_machine = debug_camera_sm,
        .curr_states = std.ArrayList(*fsm.State).init(system.allocator),
        .entities = std.ArrayList(ecs.entity_t).init(system.allocator),
        .blob_array = blk: {
            const blob_array = BlobArray(16).create(system.allocator, debug_camera_sm.max_state_size);
            break :blk blob_array;
        },
    }) catch unreachable;

    const fps_camera_sm = blk: {
        const initial_state = StateCameraFPS.create(sm_ctx);
        var states = std.ArrayList(fsm.State).init(system.allocator);
        states.append(initial_state) catch unreachable;
        const sm = fsm.StateMachine.create("fps_camera", states, "fps_camera");
        system.state_machines.append(sm) catch unreachable;
        break :blk &system.state_machines.items[system.state_machines.items.len - 1];
    };

    system.instances.append(.{
        .state_machine = fps_camera_sm,
        .curr_states = std.ArrayList(*fsm.State).init(system.allocator),
        .entities = std.ArrayList(ecs.entity_t).init(system.allocator),
        .blob_array = blk: {
            const blob_array = BlobArray(16).create(system.allocator, fps_camera_sm.max_state_size);
            break :blk blob_array;
        },
    }) catch unreachable;

    const giant_ant_sm = blk: {
        const initial_state = StateGiantAnt.create(sm_ctx);
        var states = std.ArrayList(fsm.State).init(system.allocator);
        states.append(initial_state) catch unreachable;
        const sm = fsm.StateMachine.create("giant_ant", states, "giant_ant");
        system.state_machines.append(sm) catch unreachable;
        break :blk &system.state_machines.items[system.state_machines.items.len - 1];
    };

    system.instances.append(.{
        .state_machine = giant_ant_sm,
        .curr_states = std.ArrayList(*fsm.State).init(system.allocator),
        .entities = std.ArrayList(ecs.entity_t).init(system.allocator),
        .blob_array = blk: {
            const blob_array = BlobArray(16).create(system.allocator, giant_ant_sm.max_state_size);
            break :blk blob_array;
        },
    }) catch unreachable;
}

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "State Machine System: Update", 0x00_ff_00_ff);
    defer trazy_zone.End();

    defer ecs.iter_fini(iter.iter);
    const system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    const dt4 = zm.f32x4s(iter.iter.delta_time);

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

    for (system.instances.items) |*instance| {
        for (instance.curr_states.items) |fsm_state| {
            const ctx = fsm.StateFuncContext{
                .state = fsm_state,
                .blob_array = &instance.blob_array,
                .allocator = system.allocator,
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

fn onSetCIFSM(it: *ecsu.Iterator(ObserverCallback)) void {
    const observer = @as(*ecs.observer_t, @ptrCast(@alignCast(it.iter.ctx)));
    const system: *SystemState = @ptrCast(@alignCast(observer.*.ctx));
    while (it.next()) |_| {
        const ci_ptr = ecs.field_w_size(it.iter, @sizeOf(fd.CIFSM), @as(i32, @intCast(it.index))).?;
        const ci = @as(*fd.CIFSM, @ptrCast(@alignCast(ci_ptr)));

        const smi_i = blk_smi_i: {
            const state_machine = blk_sm: {
                for (system.state_machines.items) |*sm| {
                    if (sm.name.eqlHash(ci.state_machine_hash)) {
                        break :blk_sm sm;
                    }
                }
                unreachable;
            };

            for (system.instances.items, 0..) |*smi, i| {
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
        const ent = ecsu.Entity.init(it.world().world, it.entity());
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
