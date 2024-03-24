const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");

const renderer = @import("../renderer/renderer.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;

const max_instances = 1000;

const UIInstanceData = struct {
    rect: [4]f32,
    color: [4]f32,
    texture_index: u32,
    _padding: [3]u32,
};

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    sys: ecs.entity_t,

    instance_data_buffers: [renderer.buffered_frames_count]renderer.BufferHandle,
    instance_data: std.ArrayList(UIInstanceData),
    ui_buffer_indices: *renderer.HackyUIBuffersIndices,

    query_ui: ecsu.Query,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, ecsu_world: ecsu.World, ui_buffer_indices: *renderer.HackyUIBuffersIndices) !*SystemState {
    const instance_data_buffers = blk: {
        var buffers: [renderer.buffered_frames_count]renderer.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = max_instances * @sizeOf(UIInstanceData),
            };
            buffers[buffer_index] = renderer.createBuffer(buffer_data, @sizeOf(UIInstanceData), "UI Instance Buffer");
        }

        break :blk buffers;
    };

    const instance_data = std.ArrayList(UIInstanceData).init(allocator);

    const system = allocator.create(SystemState) catch unreachable;
    const sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });

    var query_builder_ui = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_ui.withReadonly(fd.UIImageComponent);
    const query_ui = query_builder_ui.buildQuery();

    system.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .sys = sys,
        .instance_data_buffers = instance_data_buffers,
        .instance_data = instance_data,
        .query_ui = query_ui,
        .ui_buffer_indices = ui_buffer_indices,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.query_ui.deinit();
    system.instance_data.deinit();
    system.allocator.destroy(system);
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    defer ecs.iter_fini(iter.iter);
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));

    const frame_index = renderer.frameIndex();

    var entity_iter_ui = system.query_ui.iterator(struct {
        ui_image: *const fd.UIImageComponent,
    });

    system.instance_data.clearRetainingCapacity();

    while (entity_iter_ui.next()) |comps| {
        const ui_image = comps.ui_image;
        const ui_material = ui_image.material;
        system.instance_data.append(.{
            .rect = [4]f32{ ui_image.rect[0], ui_image.rect[1], ui_image.rect[2], ui_image.rect[3] },
            .color = [4]f32{ ui_material.color[0], ui_material.color[1], ui_material.color[2], ui_material.color[3] },
            .texture_index = renderer.textureBindlessIndex(ui_material.texture),
            ._padding = [3]u32{ 42, 42, 42 },
        }) catch unreachable;
    }

    const instance_data_slice = renderer.Slice{
        .data = @ptrCast(system.instance_data.items),
        .size = system.instance_data.items.len * @sizeOf(UIInstanceData),
    };
    renderer.updateBuffer(instance_data_slice, system.instance_data_buffers[frame_index]);

    system.ui_buffer_indices.ui_instance_buffer_index = renderer.bufferBindlessIndex(system.instance_data_buffers[frame_index]);
    system.ui_buffer_indices.ui_instance_count = @intCast(system.instance_data.items.len);
}
