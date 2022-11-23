const std = @import("std");
const assert = std.debug.assert;
const math = std.math;

const glfw = @import("glfw");
const zgpu = @import("zgpu");
const zm = @import("zmath");
const zmesh = @import("zmesh");
const flecs = @import("flecs");
const wgsl = @import("procedural_mesh_system_wgsl.zig");
const wgpu = zgpu.wgpu;

const gfx = @import("../gfx_wgpu.zig");
const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;

const IndexType = zmesh.Shape.IndexType;

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
};
const FrameUniforms = struct {
    world_to_clip: zm.Mat,
    camera_position: [3]f32,
    time: f32,
    padding1: u32,
    padding2: u32,
    padding3: u32,
    light_count: u32,
    light_positions: [32][4]f32,
    light_radiances: [32][4]f32,
};

const DrawUniforms = struct {
    object_to_world: zm.Mat,
    basecolor_roughness: [4]f32,
};

const Mesh = struct {
    // entity: flecs.EntityId,
    id: IdLocal,
    index_offset: u32,
    vertex_offset: i32,
    num_indices: u32,
    num_vertices: u32,
};

// const SystemInit = struct {
//     arena_state: std.heap.ArenaAllocator,
//     arena_allocator: std.mem.Allocator,

//     meshes: std.ArrayList(Mesh),
//     meshes_indices: std.ArrayList(IndexType),
//     meshes_positions: std.ArrayList([3]f32),
//     meshes_normals: std.ArrayList([3]f32),

//     pub fn init(self: *SystemInit, system_allocator: std.mem.Allocator) void {
//         self.arena_state = std.heap.ArenaAllocator.init(system_allocator);
//         const arena = arena_state.allocator();

//         self.meshes = std.ArrayList(Mesh).init(system_allocator);
//         self.meshes_indices = std.ArrayList(IndexType).init(arena);
//         self.meshes_positions = std.ArrayList([3]f32).init(arena);
//         self.meshes_normals = std.ArrayList([3]f32).init(arena);
//     }

//     pub fn deinit(self: *SystemInit) void {
//         self.arena_state.deinit();
//     }

//     pub fn setupSystem(state: *SystemState) void {}
// };

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    sys: flecs.EntityId,
    // init: SystemInit,

    gfx: *gfx.GfxState,
    gctx: *zgpu.GraphicsContext,
    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,

    meshes: std.ArrayList(Mesh),
    query_camera: flecs.Query,
    query_lights: flecs.Query,
    query_mesh: flecs.Query,
    query_transform: flecs.Query,

    camera: struct {
        position: [3]f32 = .{ 0.0, 4.0, -4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.15 * math.pi,
        yaw: f32 = 0.0,
    } = .{},
};

fn appendMesh(
    id: IdLocal,
    // entity: flecs.EntityId,
    mesh: zmesh.Shape,
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_positions: *std.ArrayList([3]f32),
    meshes_normals: *std.ArrayList([3]f32),
) u64 {
    meshes.append(.{
        .id = id,
        // .entity = entity,
        .index_offset = @intCast(u32, meshes_indices.items.len),
        .vertex_offset = @intCast(i32, meshes_positions.items.len),
        .num_indices = @intCast(u32, mesh.indices.len),
        .num_vertices = @intCast(u32, mesh.positions.len),
    }) catch unreachable;

    meshes_indices.appendSlice(mesh.indices) catch unreachable;
    meshes_positions.appendSlice(mesh.positions) catch unreachable;
    meshes_normals.appendSlice(mesh.normals.?) catch unreachable;

    return meshes.items.len - 1;
}

fn initScene(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_positions: *std.ArrayList([3]f32),
    meshes_normals: *std.ArrayList([3]f32),
) void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    zmesh.init(arena);
    defer zmesh.deinit();

    {
        var mesh = zmesh.Shape.initParametricSphere(20, 20);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        _ = appendMesh(IdLocal.init("sphere"), mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }

    {
        var mesh = zmesh.Shape.initCube();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        _ = appendMesh(IdLocal.init("cube"), mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }

    {
        var mesh = zmesh.Shape.initCylinder(10, 10);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.scale(0.5, 1.0, 0.5);
        mesh.translate(0.0, 1.0, 0.0);

        // Top cap.
        var top = zmesh.Shape.initParametricDisk(10, 2);
        defer top.deinit();
        top.rotate(-math.pi * 0.5, 1.0, 0.0, 0.0);
        top.scale(0.5, 1.0, 0.5);
        top.translate(0.0, 1.0, 0.0);

        // Bottom cap.
        var bottom = zmesh.Shape.initParametricDisk(10, 2);
        defer bottom.deinit();
        bottom.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        bottom.scale(0.5, 1.0, 0.5);
        bottom.translate(0.0, 0.0, 0.0);

        mesh.merge(top);
        mesh.merge(bottom);
        mesh.unweld();
        mesh.computeNormals();

        _ = appendMesh(IdLocal.init("cylinder"), mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }

    {
        var mesh = zmesh.Shape.initCylinder(4, 4);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.scale(0.5, 1.0, 0.5);
        mesh.translate(0.0, 1.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        _ = appendMesh(IdLocal.init("tree_trunk"), mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    {
        var mesh = zmesh.Shape.initCone(4, 4);
        defer mesh.deinit();
        mesh.rotate(-math.pi * 0.5, 1.0, 0.0, 0.0);
        // mesh.scale(0.5, 1.0, 0.5);
        // mesh.translate(0.0, 1.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        _ = appendMesh(IdLocal.init("tree_crown"), mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
}

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.GfxState, flecs_world: *flecs.World) !*SystemState {
    const gctx = gfxstate.gctx;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Create a bind group layout needed for our render pipeline.
    const bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
    });
    defer gctx.releaseResource(bind_group_layout);

    const pipeline_layout = gctx.createPipelineLayout(&.{
        bind_group_layout,
        bind_group_layout,
    });
    defer gctx.releaseResource(pipeline_layout);

    const pipeline = pipeline: {
        const vs_module = zgpu.createWgslShaderModule(gctx.device, wgsl.vs, "vs");
        defer vs_module.release();

        const fs_module = zgpu.createWgslShaderModule(gctx.device, wgsl.fs, "fs");
        defer fs_module.release();

        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]wgpu.VertexAttribute{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "normal"), .shader_location = 1 },
        };
        const vertex_buffers = [_]wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};

        // Create a render pipeline.
        const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
            .vertex = wgpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = wgpu.PrimitiveState{
                .front_face = .cw,
                .cull_mode = .back,
                .topology = .triangle_list,
            },
            .depth_stencil = &wgpu.DepthStencilState{
                .format = .depth32_float,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .fragment = &wgpu.FragmentState{
                .module = fs_module,
                .entry_point = "main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
        };
        break :pipeline gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    };

    const bind_group = gctx.createBindGroup(bind_group_layout, &[_]zgpu.BindGroupEntryInfo{
        .{ .binding = 0, .buffer_handle = gctx.uniforms.buffer, .offset = 0, .size = @sizeOf(FrameUniforms) },
    });

    var meshes = std.ArrayList(Mesh).init(allocator);
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_positions = std.ArrayList([3]f32).init(arena);
    var meshes_normals = std.ArrayList([3]f32).init(arena);
    initScene(allocator, &meshes, &meshes_indices, &meshes_positions, &meshes_normals);

    const total_num_vertices = @intCast(u32, meshes_positions.items.len);
    const total_num_indices = @intCast(u32, meshes_indices.items.len);

    // Create a vertex buffer.
    const vertex_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = total_num_vertices * @sizeOf(Vertex),
    });
    {
        var vertex_data = std.ArrayList(Vertex).init(arena);
        defer vertex_data.deinit();
        vertex_data.resize(total_num_vertices) catch unreachable;

        for (meshes_positions.items) |_, i| {
            vertex_data.items[i].position = meshes_positions.items[i];
            vertex_data.items[i].normal = meshes_normals.items[i];
        }
        gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, vertex_data.items);
    }

    // Create an index buffer.
    const index_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = total_num_indices * @sizeOf(IndexType),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, IndexType, meshes_indices.items);

    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });
    // var sys_post = flecs_world.newWrappedRunSystem(name.toCString(), .post_update, fd.NOCOMP, post_update, .{ .ctx = state });

    // Queries
    var query_builder_camera = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_camera
        .withReadonly(fd.Camera)
        .withReadonly(fd.Position);
    var query_builder_lights = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_lights
        .with(fd.Light)
        .with(fd.Position);
    var query_builder_mesh = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_mesh
        .withReadonly(fd.Transform)
        .withReadonly(fd.Scale)
        .withReadonly(fd.ShapeMeshInstance);
    var query_builder_transform = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_transform
        .with(fd.Transform)
        .withReadonly(fd.Position)
        .withReadonly(fd.EulerRotation)
        .withReadonly(fd.Scale)
        .withReadonly(fd.Dynamic);

    var query_camera = query_builder_camera.buildQuery();
    var query_lights = query_builder_lights.buildQuery();
    var query_mesh = query_builder_mesh.buildQuery();
    var query_transform = query_builder_transform.buildQuery();

    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .sys = sys,
        .gfx = gfxstate,
        .gctx = gctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .meshes = meshes,
        .query_camera = query_camera,
        .query_lights = query_lights,
        .query_mesh = query_mesh,
        .query_transform = query_transform,
    };

    // flecs_world.observer(ShapeMeshDefinitionObserverCallback, .on_set, state);
    flecs_world.observer(ShapeMeshInstanceObserverCallback, .on_set, state);

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_camera.deinit();
    state.query_lights.deinit();
    state.query_mesh.deinit();
    state.query_transform.deinit();
    state.meshes.deinit();
    state.allocator.destroy(state);
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));

    const gctx = state.gctx;

    {
        var entity_iter_transform = state.query_transform.iterator(struct {
            transform: *fd.Transform,
            pos: *const fd.Position,
            rot: *const fd.EulerRotation,
            scale: *const fd.Scale,
            dynamic: *const fd.Dynamic,
        });

        while (entity_iter_transform.next()) |comps| {
            const z_scale_matrix = zm.scaling(comps.scale.x, comps.scale.y, comps.scale.z);
            const z_rot_x = zm.rotationX(comps.rot.yaw);
            const z_rot_y = zm.rotationY(comps.rot.pitch);
            const z_rot_z = zm.rotationZ(comps.rot.roll);
            const z_rot_matrix = zm.mul(z_rot_y, zm.mul(z_rot_z, z_rot_x));
            const z_translate_matrix = zm.translation(comps.pos.x, comps.pos.y, comps.pos.z);
            const z_sr_matrix = zm.mul(z_scale_matrix, z_rot_matrix);
            const z_srt_matrix = zm.mul(z_sr_matrix, z_translate_matrix);
            zm.storeMat43(&comps.transform.matrix, z_srt_matrix);
        }
    }

    const CameraQueryComps = struct {
        cam: *const fd.Camera,
        pos: *const fd.Position,
    };
    var camera_comps: ?CameraQueryComps = null;
    {
        var entity_iter_camera = state.query_camera.iterator(CameraQueryComps);
        while (entity_iter_camera.next()) |comps| {
            if (comps.cam.active) {
                camera_comps = comps;
                break;
            }
        }

        if (camera_comps == null) {
            return;
        }
    }

    const cam = camera_comps.?.cam;
    const cam_world_to_clip = zm.loadMat(cam.world_to_clip[0..]);

    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        pass: {
            const vb_info = gctx.lookupResourceInfo(state.vertex_buffer) orelse break :pass;
            const ib_info = gctx.lookupResourceInfo(state.index_buffer) orelse break :pass;
            const pipeline = gctx.lookupResource(state.pipeline) orelse break :pass;
            const bind_group = gctx.lookupResource(state.bind_group) orelse break :pass;
            const depth_view = gctx.lookupResource(state.gfx.*.depth_texture_view) orelse break :pass;

            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .load,
                .store_op = .store,
            }};
            const depth_attachment = wgpu.RenderPassDepthStencilAttachment{
                .view = depth_view,
                .depth_load_op = .clear, // else .load,
                .depth_store_op = .store,
                .depth_clear_value = 1.0,
            };
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
                .depth_stencil_attachment = &depth_attachment,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
            pass.setIndexBuffer(
                ib_info.gpuobj.?,
                if (IndexType == u16) .uint16 else .uint32,
                0,
                ib_info.size,
            );

            pass.setPipeline(pipeline);

            {
                const mem = gctx.uniformsAllocate(FrameUniforms, 1);
                mem.slice[0].world_to_clip = zm.transpose(cam_world_to_clip);
                mem.slice[0].camera_position = camera_comps.?.pos.elemsConst().*;
                mem.slice[0].time = @floatCast(f32, state.gctx.stats.time);
                mem.slice[0].light_count = 0;

                var entity_iter_lights = state.query_lights.iterator(struct {
                    light: *fd.Light,
                    position: *fd.Position,
                });

                var light_i: u32 = 0;
                while (entity_iter_lights.next()) |comps| {
                    std.mem.copy(f32, mem.slice[0].light_positions[light_i][0..], comps.position.elemsConst().*[0..]);
                    std.mem.copy(f32, mem.slice[0].light_radiances[light_i][0..3], comps.light.radiance.elemsConst().*[0..]);
                    mem.slice[0].light_radiances[light_i][3] = comps.light.range;
                    // std.debug.print("light: {any}{any}\n", .{ light_i, mem.slice[0].light_positions[light_i] });

                    light_i += 1;
                }
                mem.slice[0].light_count = light_i;

                pass.setBindGroup(0, bind_group, &.{mem.offset});
                // std.debug.print("mem: {any} / {any} / {any}\n", .{ @sizeOf(FrameUniforms), mem.offset, mem.slice[0].camera_position });
            }

            var entity_iter_mesh = state.query_mesh.iterator(struct {
                transform: *const fd.Transform,
                scale: *const fd.Scale,
                mesh: *const fd.ShapeMeshInstance,
            });
            while (entity_iter_mesh.next()) |comps| {
                // const scale_matrix = zm.scaling(comps.scale.x, comps.scale.y, comps.scale.z);
                // const transform = zm.loadMat43(comps.transform.matrix[0..]);
                // const object_to_world = zm.mul(scale_matrix, transform);
                const object_to_world = zm.loadMat43(comps.transform.matrix[0..]);

                const mem = gctx.uniformsAllocate(DrawUniforms, 1);
                mem.slice[0].object_to_world = zm.transpose(object_to_world);
                mem.slice[0].basecolor_roughness[0] = comps.mesh.basecolor_roughness.r;
                mem.slice[0].basecolor_roughness[1] = comps.mesh.basecolor_roughness.g;
                mem.slice[0].basecolor_roughness[2] = comps.mesh.basecolor_roughness.b;
                mem.slice[0].basecolor_roughness[3] = comps.mesh.basecolor_roughness.roughness;

                pass.setBindGroup(1, bind_group, &.{mem.offset});

                // Draw.
                pass.drawIndexed(
                    state.meshes.items[comps.mesh.mesh_index].num_indices,
                    1,
                    state.meshes.items[comps.mesh.mesh_index].index_offset,
                    state.meshes.items[comps.mesh.mesh_index].vertex_offset,
                    0,
                );
            }
        }

        break :commands encoder.finish(null);
    };
    state.gfx.command_buffers.append(commands) catch unreachable;
}

// const ShapeMeshDefinitionObserverCallback = struct {
//     comp: *const fd.CIShapeMeshDefinition,

//     pub const name = "CIShapeMeshDefinition";
//     pub const run = onSetCIShapeMeshDefinition;
// };

const ShapeMeshInstanceObserverCallback = struct {
    comp: *const fd.CIShapeMeshInstance,

    pub const name = "CIShapeMeshInstance";
    pub const run = onSetCIShapeMeshInstance;
};

// fn onSetCIShapeMeshDefinition(it: *flecs.Iterator(ShapeMeshDefinitionObserverCallback)) void {
//     var observer = @ptrCast(*flecs.c.ecs_observer_t, @alignCast(@alignOf(flecs.c.ecs_observer_t), it.iter.ctx));
//     var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), observer.*.ctx));

//     while (it.next()) |_| {
//         const ci_ptr = flecs.c.ecs_term_w_size(it.iter, @sizeOf(fd.CIShapeMeshDefinition), @intCast(i32, it.index)).?;
//         var ci = @ptrCast(*fd.CIShapeMeshDefinition, @alignCast(@alignOf(fd.CIShapeMeshDefinition), ci_ptr));

//         const ent = it.entity();
//         const mesh_index = appendMesh(
//             ci.id,
//             ent.id,
//             ci.shape,
//             &state.meshes,
//             &state.meshes_indices,
//             &state.meshes_positions,
//             &state.meshes_normals,
//         );

//         ent.remove(fd.CIShapeMeshDefinition);
//         ent.set(fd.ShapeMeshDefinition{
//             .id = ci.id,
//             .mesh_index = mesh_index,
//         });
//     }
// }

fn onSetCIShapeMeshInstance(it: *flecs.Iterator(ShapeMeshInstanceObserverCallback)) void {
    var observer = @ptrCast(*flecs.c.ecs_observer_t, @alignCast(@alignOf(flecs.c.ecs_observer_t), it.iter.ctx));
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), observer.*.ctx));

    while (it.next()) |_| {
        const ci_ptr = flecs.c.ecs_term_w_size(it.iter, @sizeOf(fd.CIShapeMeshInstance), @intCast(i32, it.index)).?;
        var ci = @ptrCast(*fd.CIShapeMeshInstance, @alignCast(@alignOf(fd.CIShapeMeshInstance), ci_ptr));

        const mesh_index = mesh_blk: {
            for (state.meshes.items) |mesh, i| {
                if (mesh.id.eqlHash(ci.id)) {
                    break :mesh_blk i;
                }
            }
            unreachable;
        };

        const ent = it.entity();
        ent.remove(fd.CIShapeMeshInstance);
        ent.set(fd.ShapeMeshInstance{
            .mesh_index = mesh_index,
            .basecolor_roughness = ci.basecolor_roughness,
        });
    }
}
