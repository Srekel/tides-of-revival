const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const gfx = @import("../gfx_wgpu.zig");
const zbt = @import("zbullet");
const zm = @import("zmath");
const znoise = @import("znoise");

const glfw = @import("glfw");
const zgpu = @import("zgpu");
const gpu = @import("gpu");
const zmesh = @import("zmesh");
const wgsl = @import("procedural_mesh_system_wgsl.zig");

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;

const IndexType = u32;
const patches_on_side = 3;
const patch_count = patches_on_side * patches_on_side;
const patch_side_vertex_count = fd.patch_width;

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
};
const FrameUniforms = struct {
    world_to_clip: zm.Mat,
    camera_position: [3]f32,
};

const DrawUniforms = struct {
    object_to_world: zm.Mat,
    basecolor_roughness: [4]f32,
};

const Mesh = struct {
    // entity: flecs.EntityId,
    index_offset: u32,
    vertex_offset: i32,
    num_indices: u32,
    num_vertices: u32,
};

const Patch = struct {
    status: enum {
        not_used,
        in_queue,
        generating_heights,
        generating_normals,
        generating_physics,
        writing_gfx,
        loaded,
    } = .not_used,
    lod: enum {
        low,
        full,
    } = .full,
    pos: [2]i32 = undefined,
    lookup: u32 = undefined,
    hash: i32 = 0,
    heights: [fd.patch_width * fd.patch_width]f32,
    vertices: [patch_side_vertex_count * patch_side_vertex_count]Vertex,
};

const max_loaded_patches = 64;

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    physics_world: zbt.World,
    sys: flecs.EntityId,

    gfx: *gfx.GfxState,
    gctx: *zgpu.GraphicsContext,
    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,
    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,
    meshes: std.ArrayList(Mesh),

    patches: std.ArrayList(Patch),
    // meshes: std.ArrayList(Mesh),
    // vertices: [max_loaded_patches][fd.patch_width]Vertex = undefined,
    // heights: [patch_count][fd.patch_width * fd.patch_width]f32,
    // entity_to_lookup: std.ArrayList(struct { id: EntityId, lookup: u32 }),

    query_loader: flecs.Query,
    query_camera: flecs.Query,
    noise: znoise.FnlGenerator,

    camera: struct {
        position: [3]f32 = .{ 0.0, 4.0, -4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.15 * math.pi,
        yaw: f32 = 0.0,
    } = .{},
};

fn initPatches(
    allocator: std.mem.Allocator,
    // state: *SystemState,
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_positions: *std.ArrayList([3]f32),
    meshes_normals: *std.ArrayList([3]f32),
) void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // meshes.resize(patch_count);
    var indices_per_patch: u32 = (fd.patch_width) * (fd.patch_width) * 6;
    var vertices_per_patch: u32 = patch_side_vertex_count * patch_side_vertex_count;

    // var indices = std.ArrayList(IndexType).init(arena);

    var patch_vertex_positions = arena.alloc([3]f32, vertices_per_patch) catch unreachable;
    var patch_vertex_normals = arena.alloc([3]f32, vertices_per_patch) catch unreachable;
    defer arena.free(patch_vertex_positions);
    defer arena.free(patch_vertex_normals);
    {
        var z: usize = 0;
        while (z < patch_side_vertex_count) : (z += 1) {
            var x: usize = 0;
            while (x < patch_side_vertex_count) : (x += 1) {
                var i = x + z * patch_side_vertex_count;
                var pos = &patch_vertex_positions[i];
                var normal = &patch_vertex_normals[i];
                pos[0] = @intToFloat(f32, x);
                pos[1] = 0;
                pos[2] = @intToFloat(f32, z);
                normal[0] = 0;
                normal[1] = 1;
                normal[2] = 0;
            }
        }
    }

    var patch_indices = arena.alloc(u32, indices_per_patch) catch unreachable;
    defer arena.free(patch_indices);
    {
        var i: u32 = 0;
        var y: u32 = 0;
        const width = @intCast(u32, fd.patch_width);
        const height = @intCast(u32, fd.patch_width);
        while (y < height - 1) : (y += 1) {
            var x: u32 = 0;
            while (x < width - 1) : (x += 1) {
                const indices_quad = [_]u32{
                    x + y * width,
                    x + (y + 1) * width,
                    x + 1 + y * width,
                    x + 1 + (y + 1) * width,
                };

                patch_indices[i + 0] = indices_quad[0];
                patch_indices[i + 1] = indices_quad[1];
                patch_indices[i + 2] = indices_quad[2];

                patch_indices[i + 3] = indices_quad[2];
                patch_indices[i + 4] = indices_quad[1];
                patch_indices[i + 5] = indices_quad[3];
                // std.debug.print("quad: {any}\n", .{indices_quad});
                // std.debug.print("indices: {any}\n", .{patch_indices[i .. i + 6]});
                // std.debug.print("tri: {any} {any} {any}\n", .{
                //     patch_vertex_positions[patch_indices[i + 0]],
                //     patch_vertex_positions[patch_indices[i + 1]],
                //     patch_vertex_positions[patch_indices[i + 2]],
                // });
                // std.debug.print("tri: {any} {any} {any}\n", .{
                //     patch_vertex_positions[patch_indices[i + 3]],
                //     patch_vertex_positions[patch_indices[i + 4]],
                //     patch_vertex_positions[patch_indices[i + 5]],
                // });
                i += 6;
            }
        }
    }

    var patch_i: u32 = 0;
    while (patch_i < patch_count) : (patch_i += 1) {
        meshes.append(.{
            // .id = id,
            // .entity = entity,
            .index_offset = @intCast(u32, meshes_indices.items.len),
            .vertex_offset = @intCast(i32, meshes_positions.items.len),
            .num_indices = @intCast(u32, indices_per_patch),
            .num_vertices = @intCast(u32, vertices_per_patch),
        }) catch unreachable;

        meshes_indices.appendSlice(patch_indices) catch unreachable;
        meshes_positions.appendSlice(patch_vertex_positions) catch unreachable;
        meshes_normals.appendSlice(patch_vertex_normals) catch unreachable;
    }
}

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.GfxState, flecs_world: *flecs.World, physics_world: zbt.World) !*SystemState {
    var query_builder_loader = flecs.QueryBuilder.init(flecs_world.*)
        .with(fd.WorldLoader)
        .with(fd.Position);
    var query_loader = query_builder_loader.buildQuery();

    var query_builder_camera = flecs.QueryBuilder.init(flecs_world.*)
        .withReadonly(fd.Camera);
    var query_camera = query_builder_camera.buildQuery();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Create a bind group layout needed for our render pipeline.
    const gctx = gfxstate.gctx;
    const bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bglBuffer(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
    });
    defer gctx.releaseResource(bind_group_layout);

    const pipeline_layout = gctx.createPipelineLayout(&.{
        bind_group_layout,
        bind_group_layout,
    });
    defer gctx.releaseResource(pipeline_layout);

    const pipeline = pipeline: {
        const vs_module = gctx.device.createShaderModule(&.{ .label = "vs", .code = .{ .wgsl = wgsl.vs } });
        defer vs_module.release();

        const fs_module = gctx.device.createShaderModule(&.{ .label = "fs", .code = .{ .wgsl = wgsl.fs } });
        defer fs_module.release();

        const color_target = gpu.ColorTargetState{
            .format = zgpu.GraphicsContext.swapchain_format,
            .blend = &.{ .color = .{}, .alpha = .{} },
        };

        const vertex_attributes = [_]gpu.VertexAttribute{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "normal"), .shader_location = 1 },
        };
        const vertex_buffer_layout = gpu.VertexBufferLayout{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        };

        // Create a render pipeline.
        const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
            .vertex = gpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
                .buffers = &.{vertex_buffer_layout},
            },
            .primitive = gpu.PrimitiveState{
                .front_face = .cw,
                .cull_mode = .back,
                .topology = .triangle_list,
            },
            .depth_stencil = &gpu.DepthStencilState{
                .format = .depth32_float,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .fragment = &gpu.FragmentState{
                .module = fs_module,
                .entry_point = "main",
                .targets = &.{color_target},
            },
        };
        break :pipeline gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    };

    const bind_group = gctx.createBindGroup(bind_group_layout, &[_]zgpu.BindGroupEntryInfo{
        .{ .binding = 0, .buffer_handle = gctx.uniforms.buffer, .offset = 0, .size = 256 },
    });

    var meshes = std.ArrayList(Mesh).init(allocator);
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_positions = std.ArrayList([3]f32).init(arena);
    var meshes_normals = std.ArrayList([3]f32).init(arena);
    initPatches(allocator, &meshes, &meshes_indices, &meshes_positions, &meshes_normals);

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

    // State
    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .physics_world = physics_world,
        .sys = sys,

        .gfx = gfxstate,
        .gctx = gctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .meshes = meshes,

        .patches = std.ArrayList(Patch).init(allocator),
        // .bodies = std.ArrayList(zbt.Body).init(),
        .query_loader = query_loader,
        .query_camera = query_camera,
        .noise = .{
            .seed = @intCast(i32, 1234),
            .fractal_type = .fbm,
            .frequency = 0.0001,
            .octaves = 20,
        },
    };

    state.patches.resize(9 * 9) catch unreachable;
    for (state.patches.items) |*patch, i| {
        patch.status = .not_used;
        patch.hash = 0;
        patch.lookup = @intCast(u32, i);
    }
    // flecs_world.observer(ObserverCallback, .on_set, state);

    return state;
}

pub fn destroy(state: *SystemState) void {
    // state.comp_query.deinit();
    state.query_loader.deinit();
    state.query_camera.deinit();
    state.meshes.deinit();
    state.allocator.destroy(state);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    _ = state.physics_world.stepSimulation(iter.iter.delta_time, .{});
    // _ = state.physics_world.stepSimulation(0.0166, .{});

    var entity_iter = state.query_loader.iterator(struct {
        loader: *fd.WorldLoader,
        position: *fd.Position,
    });

    while (entity_iter.next()) |comps| {
        var range: i32 = 0;
        while (range < comps.loader.range) : (range += 1) {
            var x: i32 = 0;
            while (x < range * 2 + 1) : (x += 1) {
                var y: i32 = 0;
                while (y < range * 2 + 1) : (y += 1) {
                    const world_x = @floatToInt(i32, comps.position.x) + x * fd.patch_width;
                    const world_y = @floatToInt(i32, comps.position.y) + y * fd.patch_width;
                    const patch_hash = @divTrunc(world_x, fd.patch_width) + 1024 * @divTrunc(world_y, fd.patch_width);

                    for (state.patches.items) |*patch| {
                        if (patch.hash == patch_hash) {
                            break;
                        }
                    } else {
                        for (state.patches.items) |*patch| {
                            if (patch.status != .not_used) {
                                continue;
                            }

                            patch.hash = patch_hash;
                            patch.pos = [_]i32{ world_x, world_y };
                            break;
                        } else {
                            unreachable;
                        }
                    }
                }
            }
        }
    }

    for (state.patches.items) |*patch| {
        patch.status =
            switch (patch.status) {
            .loaded => continue,
            .not_used => continue,
            .in_queue => continue,
            .generating_heights => blk: {
                var x: f32 = 0;
                while (x < fd.patch_width) : (x += 1) {
                    var y: f32 = 0;
                    while (y < fd.patch_width) : (y += 1) {
                        const world_x = @intToFloat(f32, patch.pos[0]) + x;
                        const world_y = @intToFloat(f32, patch.pos[1]) + y;
                        const height = state.noise.noise2(world_x, world_y);
                        const index = @floatToInt(u32, world_x) + @floatToInt(u32, world_y) * fd.patch_width;
                        // state.heights[patch.lookup][index] = height;
                        patch.heights[index] = height;
                        patch.vertices[index].position[1] = height;
                    }
                }
                break :blk .generating_normals;
            },
            .generating_normals => blk: {
                // var x: f32 = 0;
                // while (x < fd.patch_width) : (x += 1) {
                //     var y: f32 = 0;
                //     while (y < fd.patch_width) : (y += 1) {
                //         const world_x = @intToFloat(f32, patch.pos[0]) + x;
                //         const world_y = @intToFloat(f32, patch.pos[0]) + y;
                //         //     const world_y = @floatToInt(i32, comps.position.y) + y * fd.patch_width;
                //         const height = state.noise.noise2(world_x, world_y);
                //         const index = @intToFloat(i32, world_x) + @intToFloat(i32, world_y) * fd.patch_width;
                //         state.vertices[patch.lookup][index].height = height;
                //     }
                // }
                break :blk .generating_physics;
            },
            .generating_physics => blk: {
                // var x: f32 = 0;
                // while (x < fd.patch_width) : (x += 1) {
                //     var y: f32 = 0;
                //     while (y < fd.patch_width) : (y += 1) {
                //         const world_x = @intToFloat(f32, patch.pos[0]) + x;
                //         const world_y = @intToFloat(f32, patch.pos[0]) + y;
                //         //     const world_y = @floatToInt(i32, comps.position.y) + y * fd.patch_width;
                //         const height = state.noise.noise2(world_x, world_y);
                //         const index = @intToFloat(i32, world_x) + @intToFloat(i32, world_y) * fd.patch_width;
                //         state.vertices[patch.lookup][index].height = height;
                //     }
                // }
                break :blk .writing_gfx;
            },
            .writing_gfx => blk: {
                state.gctx.queue.writeBuffer(
                    state.gctx.lookupResource(state.vertex_buffer).?,
                    patch.lookup * fd.patch_width * fd.patch_width,
                    Vertex,
                    patch.vertices[0..],
                );

                break :blk .loaded;
            },
        };
    }

    const gctx = state.gctx;
    var entity_iter_camera = state.query_camera.iterator(struct { cam: *const fd.Camera });
    const camera_comps = entity_iter_camera.next().?;
    _ = camera_comps;
    const cam = camera_comps.cam;
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

            const color_attachment = gpu.RenderPassColorAttachment{
                .view = back_buffer_view,
                .load_op = .load,
                .store_op = .store,
            };
            const depth_attachment = gpu.RenderPassDepthStencilAttachment{
                .view = depth_view,
                .depth_load_op = .clear, // else .load,
                .depth_store_op = .store,
                .depth_clear_value = 1.0,
            };
            const render_pass_info = gpu.RenderPassEncoder.Descriptor{
                .color_attachments = &.{color_attachment},
                .depth_stencil_attachment = &depth_attachment,
            };
            const pass = encoder.beginRenderPass(&render_pass_info);
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
                mem.slice[0].camera_position = state.camera.position; // wut

                pass.setBindGroup(0, bind_group, &.{mem.offset});
            }

            // var entity_iter_mesh = state.query_mesh.iterator(struct {
            //     transform: *const fd.Transform,
            //     scale: *const fd.Scale,
            //     mesh: *const fd.ShapeMeshInstance,
            // });
            // while (entity_iter_mesh.next()) |comps| {

            for (state.patches.items) |*patch| {
                if (patch.status == .loaded) {
                    // const scale_matrix = zm.scaling(comps.scale.x, comps.scale.y, comps.scale.z);
                    // const transform = zm.loadMat43(comps.transform.matrix[0..]);
                    // const object_to_world = zm.mul(scale_matrix, transform);
                    const posmat = zm.translation(patch.pos[0], 0, patch.pos[1]);
                    // const object_to_world = zm.loadMat43(comps.transform.matrix[0..]);

                    const mem = gctx.uniformsAllocate(DrawUniforms, 1);
                    mem.slice[0].object_to_world = zm.transpose(posmat);
                    mem.slice[0].basecolor_roughness[0] = 1;
                    mem.slice[0].basecolor_roughness[1] = 1;
                    mem.slice[0].basecolor_roughness[2] = 1;
                    mem.slice[0].basecolor_roughness[3] = 1;

                    pass.setBindGroup(1, bind_group, &.{mem.offset});

                    // Draw.
                    var indices_per_patch: u32 = (fd.patch_width) * (fd.patch_width) * 6;
                    // var vertices_per_patch: u32 = patch_side_vertex_count * patch_side_vertex_count;
                    pass.drawIndexed(
                        indices_per_patch,
                        1,
                        patch.index_offset,
                        patch.vertex_offset,
                        0,
                    );
                }
            }
        }

        break :commands encoder.finish(null);
    };
    state.gfx.command_buffers.append(commands) catch unreachable;
}

// const ObserverCallback = struct {
//     // pos: *const fd.Position,
//     body: *const fd.CIPhysicsBody,

//     pub const name = "CIPhysicsBody";
//     pub const run = onSetCIPhysicsBody;
// };

// fn onSetCIPhysicsBody(it: *flecs.Iterator(ObserverCallback)) void {
//     var observer = @ptrCast(*flecs.c.ecs_observer_t, @alignCast(@alignOf(flecs.c.ecs_observer_t), it.iter.ctx));
//     var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), observer.*.ctx));
//     while (it.next()) |_| {
//         const ci_ptr = flecs.c.ecs_term_w_size(it.iter, @sizeOf(fd.CIPhysicsBody), @intCast(i32, it.index)).?;
//         var ci = @ptrCast(*fd.CIPhysicsBody, @alignCast(@alignOf(fd.CIPhysicsBody), ci_ptr));

//         var transform = it.entity().getMut(fd.Transform).?;
//         // const transform = [_]f32{
//         //     1.0, 0.0, 0.0, // orientation
//         //     0.0, 1.0, 0.0,
//         //     0.0, 0.0, 1.0,
//         //     pos.x, pos.y, pos.z, // translation
//         // };

//         const shape = switch (ci.shape_type) {
//             .box => zbt.BoxShape.init(&.{ ci.box.size, ci.box.size, ci.box.size }).asShape(),
//             .sphere => zbt.SphereShape.init(ci.sphere.radius).asShape(),
//         };
//         const body = zbt.Body.init(
//             ci.mass,
//             &transform.matrix,
//             shape,
//         );

//         body.setDamping(0.1, 0.1);
//         body.setRestitution(0.5);
//         body.setFriction(0.2);

//         state.physics_world.addBody(body);

//         const ent = it.entity();
//         ent.remove(fd.CIPhysicsBody);
//         ent.set(fd.PhysicsBody{
//             .body = body,
//         });
//     }
// }
