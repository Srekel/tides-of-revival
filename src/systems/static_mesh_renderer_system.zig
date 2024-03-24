const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const assert = std.debug.assert;
const math = std.math;

const zm = @import("zmath");
const zmu = @import("zmathutil");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");

const context = @import("../core/context.zig");
const renderer = @import("../renderer/renderer.zig");

const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const input = @import("../input.zig");

const ztracy = @import("ztracy");
const util = @import("../util.zig");

const InstanceData = struct {
    object_to_world: [16]f32,
};

const InstanceMaterial = struct {
    albedo_color: [4]f32,
    roughness: f32,
    metallic: f32,
    normal_intensity: f32,
    emissive_strength: f32,
    albedo_texture_index: u32,
    emissive_texture_index: u32,
    normal_texture_index: u32,
    arm_texture_index: u32,
};

const DrawCallInfo = struct {
    mesh_handle: renderer.MeshHandle,
    sub_mesh_index: u32,
};

const max_instances = 10000;
const max_instances_per_draw_call = 4096;
const max_draw_distance: f32 = 500.0;

const masked_entities_index: u32 = 0;
const opaque_entities_index: u32 = 1;
const max_entity_types: u32 = 2;

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    sys: ecs.entity_t,

    instance_data_buffers: [max_entity_types][renderer.buffered_frames_count]renderer.BufferHandle,
    instance_material_buffers: [max_entity_types][renderer.buffered_frames_count]renderer.BufferHandle,

    instance_data: [max_entity_types]std.ArrayList(InstanceData),
    instance_materials: [max_entity_types]std.ArrayList(InstanceMaterial),

    draw_calls: [max_entity_types]std.ArrayList(renderer.DrawCallInstanced),
    draw_calls_push_constants: [max_entity_types]std.ArrayList(renderer.DrawCallPushConstants),
    draw_calls_info: [max_entity_types]std.ArrayList(DrawCallInfo),

    gpu_frame_profiler_index: u64 = undefined,

    query_mesh: ecsu.Query,

    camera: struct {
        position: [3]f32 = .{ 0.0, 4.0, -4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.15 * math.pi,
        yaw: f32 = 0.0,
    } = .{},
};

pub const SystemCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
};

pub fn create(name: IdLocal, ctx: SystemCtx) !*SystemState {
    const opaque_instance_data_buffers = blk: {
        var buffers: [renderer.buffered_frames_count]renderer.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = max_instances * @sizeOf(InstanceData),
            };
            buffers[buffer_index] = renderer.createBuffer(buffer_data, @sizeOf(InstanceData), "Instance Transform Buffer: Opaque");
        }

        break :blk buffers;
    };

    const masked_instance_data_buffers = blk: {
        var buffers: [renderer.buffered_frames_count]renderer.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = max_instances * @sizeOf(InstanceData),
            };
            buffers[buffer_index] = renderer.createBuffer(buffer_data, @sizeOf(InstanceData), "Instance Transform Buffer: Masked");
        }

        break :blk buffers;
    };

    const opaque_instance_material_buffers = blk: {
        var buffers: [renderer.buffered_frames_count]renderer.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = max_instances * @sizeOf(InstanceMaterial),
            };
            buffers[buffer_index] = renderer.createBuffer(buffer_data, @sizeOf(InstanceMaterial), "Instance Material Buffer: Opaque");
        }

        break :blk buffers;
    };

    const masked_instance_material_buffers = blk: {
        var buffers: [renderer.buffered_frames_count]renderer.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = max_instances * @sizeOf(InstanceMaterial),
            };
            buffers[buffer_index] = renderer.createBuffer(buffer_data, @sizeOf(InstanceMaterial), "Instance Material Buffer: Masked");
        }

        break :blk buffers;
    };

    const allocator = ctx.allocator;
    const ecsu_world = ctx.ecsu_world;

    const draw_calls = [max_entity_types]std.ArrayList(renderer.DrawCallInstanced){ std.ArrayList(renderer.DrawCallInstanced).init(allocator), std.ArrayList(renderer.DrawCallInstanced).init(allocator) };
    const draw_calls_push_constants = [max_entity_types]std.ArrayList(renderer.DrawCallPushConstants){ std.ArrayList(renderer.DrawCallPushConstants).init(allocator), std.ArrayList(renderer.DrawCallPushConstants).init(allocator) };
    const draw_calls_info = [max_entity_types]std.ArrayList(DrawCallInfo){ std.ArrayList(DrawCallInfo).init(allocator), std.ArrayList(DrawCallInfo).init(allocator) };

    const instance_data = [max_entity_types]std.ArrayList(InstanceData){ std.ArrayList(InstanceData).init(allocator), std.ArrayList(InstanceData).init(allocator) };
    const instance_materials = [max_entity_types]std.ArrayList(InstanceMaterial){ std.ArrayList(InstanceMaterial).init(allocator), std.ArrayList(InstanceMaterial).init(allocator) };

    const system = allocator.create(SystemState) catch unreachable;
    const sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });
    // var sys_post = ecsu_world.newWrappedRunSystem(name.toCString(), .post_update, fd.NOCOMP, post_update, .{ .ctx = system });

    // Queries
    var query_builder_mesh = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_mesh
        .withReadonly(fd.Transform)
        .withReadonly(fd.StaticMeshComponent);
    const query_mesh = query_builder_mesh.buildQuery();

    system.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .renderer = ctx.renderer,
        .sys = sys,
        .instance_data_buffers = .{ masked_instance_data_buffers, opaque_instance_data_buffers },
        .instance_material_buffers = .{ masked_instance_material_buffers, opaque_instance_material_buffers },
        .draw_calls = draw_calls,
        .draw_calls_push_constants = draw_calls_push_constants,
        .draw_calls_info = draw_calls_info,
        .instance_data = instance_data,
        .instance_materials = instance_materials,
        .query_mesh = query_mesh,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.query_mesh.deinit();
    system.instance_data[opaque_entities_index].deinit();
    system.instance_data[masked_entities_index].deinit();
    system.instance_materials[opaque_entities_index].deinit();
    system.instance_materials[masked_entities_index].deinit();
    system.draw_calls[opaque_entities_index].deinit();
    system.draw_calls[masked_entities_index].deinit();
    system.draw_calls_push_constants[opaque_entities_index].deinit();
    system.draw_calls_push_constants[masked_entities_index].deinit();
    system.draw_calls_info[opaque_entities_index].deinit();
    system.draw_calls_info[masked_entities_index].deinit();
    system.allocator.destroy(system);
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Static Mesh Renderer", 0x00_ff_ff_00);
    defer trazy_zone.End();

    defer ecs.iter_fini(iter.iter);
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));

    const frame_index = renderer.frameIndex();

    // TODO(gmodarelli): We need the camera for frustum culling
    var cam_ent = util.getActiveCameraEnt(system.ecsu_world);
    const cam_comps = cam_ent.getComps(struct {
        cam: *const fd.Camera,
        transform: *const fd.Transform,
    });
    // const cam = cam_comps.cam;
    const camera_position = cam_comps.transform.getPos00();

    var entity_iter_mesh = system.query_mesh.iterator(struct {
        transform: *const fd.Transform,
        mesh: *const fd.StaticMeshComponent,
    });

    // Reset transforms, materials and draw calls array list
    for (0..max_entity_types) |entity_type_index| {
        system.instance_data[entity_type_index].clearRetainingCapacity();
        system.instance_materials[entity_type_index].clearRetainingCapacity();
        system.draw_calls[entity_type_index].clearRetainingCapacity();
        system.draw_calls_push_constants[entity_type_index].clearRetainingCapacity();
        system.draw_calls_info[entity_type_index].clearRetainingCapacity();
    }

    // Iterate over all renderable meshes, perform frustum culling and generate instance transforms and materials
    const loop1 = ztracy.ZoneNC(@src(), "Static Mesh Renderer: Culling and Batching", 0x00_ff_ff_00);
    while (entity_iter_mesh.next()) |comps| {
        const sub_mesh_count = renderer.getSubMeshCount(comps.mesh.mesh_handle);
        if (sub_mesh_count == 0) continue;

        const z_world_position = zm.loadArr3(comps.transform.getPos00());
        if (zm.lengthSq3(zm.loadArr3(camera_position) - z_world_position)[0] > (max_draw_distance * max_draw_distance)) {
            continue;
        }

        const z_world = zm.loadMat43(comps.transform.matrix[0..]);
        // TODO(gmodarelli): Store bounding boxes into The-Forge mesh's user data
        // const bb_ws = mesh.bounding_box.calculateBoundingBoxCoordinates(z_world);
        // if (!cam.isVisible(bb_ws.center, bb_ws.radius)) {
        //     continue;
        // }

        var draw_call_info = DrawCallInfo{
            .mesh_handle = comps.mesh.mesh_handle,
            .sub_mesh_index = undefined,
        };

        for (0..sub_mesh_count) |sub_mesh_index| {
            draw_call_info.sub_mesh_index = @intCast(sub_mesh_index);

            const material = comps.mesh.materials[sub_mesh_index];
            const entity_type_index = if (material.surface_type == .@"opaque") opaque_entities_index else masked_entities_index;

            system.instance_materials[entity_type_index].append(.{
                .albedo_color = [4]f32{ material.base_color.r, material.base_color.g, material.base_color.b, 1.0 },
                .roughness = material.roughness,
                .metallic = material.metallic,
                .normal_intensity = material.normal_intensity,
                .emissive_strength = material.emissive_strength,
                .albedo_texture_index = system.renderer.getTextureBindlessIndex(material.albedo),
                .emissive_texture_index = system.renderer.getTextureBindlessIndex(material.emissive),
                .normal_texture_index = system.renderer.getTextureBindlessIndex(material.normal),
                .arm_texture_index = system.renderer.getTextureBindlessIndex(material.arm),
            }) catch unreachable;

            system.draw_calls_info[entity_type_index].append(draw_call_info) catch unreachable;

            var instance_data: InstanceData = undefined;
            zm.storeMat(&instance_data.object_to_world, z_world);
            system.instance_data[entity_type_index].append(instance_data) catch unreachable;
        }
    }
    loop1.End();

    const loop2 = ztracy.ZoneNC(@src(), "Static Mesh Renderer: Rendering", 0x00_ff_ff_00);
    for (0..max_entity_types) |entity_type_index| {
        var start_instance_location: u32 = 0;
        var current_draw_call: renderer.DrawCallInstanced = undefined;

        const instance_data_buffer_index = renderer.bufferBindlessIndex(system.instance_data_buffers[entity_type_index][frame_index]);
        const instance_material_buffer_index = renderer.bufferBindlessIndex(system.instance_material_buffers[entity_type_index][frame_index]);

        if (system.draw_calls_info[entity_type_index].items.len == 0) continue;

        for (system.draw_calls_info[entity_type_index].items, 0..) |draw_call_info, i| {
            if (i == 0) {
                current_draw_call = .{
                    .mesh_handle = draw_call_info.mesh_handle,
                    .sub_mesh_index = draw_call_info.sub_mesh_index,
                    .instance_count = 1,
                    .start_instance_location = start_instance_location,
                };

                start_instance_location += 1;

                if (i == system.draw_calls_info[entity_type_index].items.len - 1) {
                    system.draw_calls[entity_type_index].append(current_draw_call) catch unreachable;
                    system.draw_calls_push_constants[entity_type_index].append(.{
                        .start_instance_location = current_draw_call.start_instance_location,
                        .instance_material_buffer_index = instance_material_buffer_index,
                        .instance_data_buffer_index = instance_data_buffer_index,
                    }) catch unreachable;
                }
                continue;
            }

            if (current_draw_call.mesh_handle.id == draw_call_info.mesh_handle.id and current_draw_call.sub_mesh_index == draw_call_info.sub_mesh_index) {
                current_draw_call.instance_count += 1;
                start_instance_location += 1;

                if (i == system.draw_calls_info[entity_type_index].items.len - 1) {
                    system.draw_calls[entity_type_index].append(current_draw_call) catch unreachable;
                    system.draw_calls_push_constants[entity_type_index].append(.{
                        .start_instance_location = current_draw_call.start_instance_location,
                        .instance_material_buffer_index = instance_material_buffer_index,
                        .instance_data_buffer_index = instance_data_buffer_index,
                    }) catch unreachable;
                }
            } else {
                system.draw_calls[entity_type_index].append(current_draw_call) catch unreachable;
                system.draw_calls_push_constants[entity_type_index].append(.{
                    .start_instance_location = current_draw_call.start_instance_location,
                    .instance_material_buffer_index = instance_material_buffer_index,
                    .instance_data_buffer_index = instance_data_buffer_index,
                }) catch unreachable;

                current_draw_call = .{
                    .mesh_handle = draw_call_info.mesh_handle,
                    .sub_mesh_index = draw_call_info.sub_mesh_index,
                    .instance_count = 1,
                    .start_instance_location = start_instance_location,
                };

                start_instance_location += 1;

                if (i == system.draw_calls_info[entity_type_index].items.len - 1) {
                    system.draw_calls[entity_type_index].append(current_draw_call) catch unreachable;
                    system.draw_calls_push_constants[entity_type_index].append(.{
                        .start_instance_location = current_draw_call.start_instance_location,
                        .instance_material_buffer_index = instance_material_buffer_index,
                        .instance_data_buffer_index = instance_data_buffer_index,
                    }) catch unreachable;
                }
            }
        }

        const instance_data_slice = renderer.Slice{
            .data = @ptrCast(system.instance_data[entity_type_index].items),
            .size = system.instance_data[entity_type_index].items.len * @sizeOf(InstanceData),
        };
        renderer.updateBuffer(instance_data_slice, system.instance_data_buffers[entity_type_index][frame_index]);

        const instance_material_slice = renderer.Slice{
            .data = @ptrCast(system.instance_materials[entity_type_index].items),
            .size = system.instance_materials[entity_type_index].items.len * @sizeOf(InstanceMaterial),
        };
        renderer.updateBuffer(instance_material_slice, system.instance_material_buffers[entity_type_index][frame_index]);

        if (entity_type_index == masked_entities_index) {
            renderer.registerLitMaskedDrawCalls(.{
                .data = @ptrCast(system.draw_calls[entity_type_index].items),
                .size = system.draw_calls[entity_type_index].items.len * @sizeOf(renderer.DrawCallInstanced),
            }, .{
                .data = @ptrCast(system.draw_calls_push_constants[entity_type_index].items),
                .size = system.draw_calls_push_constants[entity_type_index].items.len * @sizeOf(renderer.DrawCallPushConstants),
            });
        } else {
            renderer.registerLitOpaqueDrawCalls(.{
                .data = @ptrCast(system.draw_calls[entity_type_index].items),
                .size = system.draw_calls[entity_type_index].items.len * @sizeOf(renderer.DrawCallInstanced),
            }, .{
                .data = @ptrCast(system.draw_calls_push_constants[entity_type_index].items),
                .size = system.draw_calls_push_constants[entity_type_index].items.len * @sizeOf(renderer.DrawCallPushConstants),
            });
        }
    }

    loop2.End();
}

fn pickLOD(camera_position: [3]f32, entity_position: [3]f32, draw_distance: f32, lod_count: u32) u32 {
    if (lod_count == 1) {
        return 0;
    }

    const z_camera_postion = zm.loadArr3(camera_position);
    const z_entity_postion = zm.loadArr3(entity_position);
    const squared_distance: f32 = zm.lengthSq3(z_camera_postion - z_entity_postion)[0];

    const squared_draw_distance = draw_distance * draw_distance;
    const t = squared_distance / squared_draw_distance;

    // TODO(gmodarelli): Store these LODs percentages in the Mesh itself.
    // assert(lod_count == 4);
    if (t <= 0.05) {
        return 0;
    } else if (t <= 0.1) {
        return @min(lod_count - 1, 1);
    } else if (t <= 0.2) {
        return @min(lod_count - 1, 2);
    } else {
        return @min(lod_count - 1, 3);
    }
}
