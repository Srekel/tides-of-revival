const std = @import("std");
const math = std.math;

const glfw = @import("glfw");
const zgpu = @import("zgpu");
const gpu = zgpu.gpu;
const zm = @import("zmath");
const zmesh = @import("zmesh");
const flecs = @import("flecs");
const wgsl = @import("procedural_mesh_system_wgsl.zig");
const znoise = @import("znoise");

const gfx = @import("../gfx_wgpu.zig");
const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;

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
    index_offset: u32,
    vertex_offset: i32,
    num_indices: u32,
    num_vertices: u32,
};

const Drawable = struct {
    mesh_index: u32,
    position: [3]f32,
    basecolor_roughness: [4]f32,
};

const SystemState = struct {
    allocator: std.mem.Allocator,
    world: *flecs.World,
    sys: flecs.EntityId,

    gfx: *gfx.GfxState,
    gctx: *zgpu.GraphicsContext,
    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,

    meshes: std.ArrayList(Mesh),
    drawables: std.ArrayList(Drawable),

    camera: struct {
        position: [3]f32 = .{ 0.0, 4.0, -4.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.15 * math.pi,
        yaw: f32 = 0.0,
    } = .{},

    lol: f32,
};

var lol: f32 = 0;

fn appendMesh(
    mesh: zmesh.Shape,
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(u16),
    meshes_positions: *std.ArrayList([3]f32),
    meshes_normals: *std.ArrayList([3]f32),
) void {
    meshes.append(.{
        .index_offset = @intCast(u32, meshes_indices.items.len),
        .vertex_offset = @intCast(i32, meshes_positions.items.len),
        .num_indices = @intCast(u32, mesh.indices.len),
        .num_vertices = @intCast(u32, mesh.positions.len),
    }) catch unreachable;

    meshes_indices.appendSlice(mesh.indices) catch unreachable;
    meshes_positions.appendSlice(mesh.positions) catch unreachable;
    meshes_normals.appendSlice(mesh.normals.?) catch unreachable;
}

fn initScene(
    allocator: std.mem.Allocator,
    drawables: *std.ArrayList(Drawable),
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(u16),
    meshes_positions: *std.ArrayList([3]f32),
    meshes_normals: *std.ArrayList([3]f32),
) void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    zmesh.init(arena);
    defer zmesh.deinit();

    // Trefoil knot.
    {
        var mesh = zmesh.Shape.initTrefoilKnot(10, 128, 0.8);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ 0, 1, 0 },
            .basecolor_roughness = .{ 0.0, 0.7, 0.0, 0.6 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Parametric sphere.
    {
        var mesh = zmesh.Shape.initParametricSphere(20, 20);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ 3, 1, 0 },
            .basecolor_roughness = .{ 0.7, 0.0, 0.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Icosahedron.
    {
        var mesh = zmesh.Shape.initIcosahedron();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ -3, 1, 0 },
            .basecolor_roughness = .{ 0.7, 0.6, 0.0, 0.4 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Dodecahedron.
    {
        var mesh = zmesh.Shape.initDodecahedron();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ 0, 1, 3 },
            .basecolor_roughness = .{ 0.0, 0.1, 1.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Cylinder with top and bottom caps.
    {
        var disk = zmesh.Shape.initParametricDisk(10, 2);
        defer disk.deinit();
        disk.invert(0, 0);

        var cylinder = zmesh.Shape.initCylinder(10, 4);
        defer cylinder.deinit();

        cylinder.merge(disk);
        cylinder.translate(0, 0, -1);
        disk.invert(0, 0);
        cylinder.merge(disk);

        cylinder.scale(0.5, 0.5, 2);
        cylinder.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);

        cylinder.unweld();
        cylinder.computeNormals();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ -3, 0, 3 },
            .basecolor_roughness = .{ 1.0, 0.0, 0.0, 0.3 },
        }) catch unreachable;

        appendMesh(cylinder, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Torus.
    {
        var mesh = zmesh.Shape.initTorus(10, 20, 0.2);
        defer mesh.deinit();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ 3, 1.5, 3 },
            .basecolor_roughness = .{ 1.0, 0.5, 0.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Subdivided sphere.
    {
        var mesh = zmesh.Shape.initSubdividedSphere(3);
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ 3, 1, 6 },
            .basecolor_roughness = .{ 0.0, 1.0, 0.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Tetrahedron.
    {
        var mesh = zmesh.Shape.initTetrahedron();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ 0, 0.5, 6 },
            .basecolor_roughness = .{ 1.0, 0.0, 1.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Octahedron.
    {
        var mesh = zmesh.Shape.initOctahedron();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ -3, 1, 6 },
            .basecolor_roughness = .{ 0.2, 0.0, 1.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Rock.
    {
        var rock = zmesh.Shape.initRock(123, 4);
        defer rock.deinit();
        rock.unweld();
        rock.computeNormals();

        drawables.append(.{
            .mesh_index = @intCast(u32, meshes.items.len),
            .position = .{ -6, 0, 3 },
            .basecolor_roughness = .{ 1.0, 1.0, 1.0, 1.0 },
        }) catch unreachable;

        appendMesh(rock, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Custom parametric (simple terrain).
    // {
    //     const gen = znoise.FnlGenerator{
    //         .fractal_type = .fbm,
    //         .frequency = 2.0,
    //         .octaves = 5,
    //         .lacunarity = 2.02,
    //     };
    //     const local = struct {
    //         fn terrain(uv: *const [2]f32, position: *[3]f32, userdata: ?*anyopaque) callconv(.C) void {
    //             _ = userdata;
    //             position[0] = uv[0];
    //             position[1] = 0.025 * gen.noise2(uv[0], uv[1]);
    //             position[2] = uv[1];
    //         }
    //     };
    //     var ground = zmesh.Shape.initParametric(local.terrain, 40, 40, null);
    //     defer ground.deinit();
    //     ground.translate(-0.5, -0.0, -0.5);
    //     ground.invert(0, 0);
    //     ground.scale(20, 20, 20);
    //     ground.computeNormals();

    //     drawables.append(.{
    //         .mesh_index = @intCast(u32, meshes.items.len),
    //         .position = .{ 0, 0, 0 },
    //         .basecolor_roughness = .{ 0.1, 0.1, 0.1, 1.0 },
    //     }) catch unreachable;

    //     appendMesh(ground, meshes, meshes_indices, meshes_positions, meshes_normals);
    // }
}

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.GfxState, world: *flecs.World) !*SystemState {
    const gctx = gfxstate.gctx;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Create a bind group layout needed for our render pipeline.
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

    var drawables = std.ArrayList(Drawable).init(allocator);
    var meshes = std.ArrayList(Mesh).init(allocator);
    var meshes_indices = std.ArrayList(u16).init(arena);
    var meshes_positions = std.ArrayList([3]f32).init(arena);
    var meshes_normals = std.ArrayList([3]f32).init(arena);
    initScene(allocator, &drawables, &meshes, &meshes_indices, &meshes_positions, &meshes_normals);

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
        .size = total_num_indices * @sizeOf(u16),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, u16, meshes_indices.items);

    var state = allocator.create(SystemState) catch unreachable;
    var sys = world.newWrappedRunSystem(name.toCString(), .on_update, fd.ComponentData, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .world = world,
        .sys = sys,
        .gfx = gfxstate,
        .gctx = gctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .lol = lol,
        .meshes = meshes,
        .drawables = drawables,
    };
    lol += 0.2;
    return state;
}

pub fn destroy(state: *SystemState) void {
    state.meshes.deinit();
    state.drawables.deinit();
    state.allocator.destroy(state);
}

fn update(iter: *flecs.Iterator(fd.ComponentData)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));

    const gctx = state.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;

    const cam_world_to_view = zm.lookAtLh(
        zm.f32x4(3.0, 3.0, -3.0, 1.0),
        zm.f32x4(0.0, 0.0, 0.0, 1.0),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(
        0.25 * math.pi,
        @intToFloat(f32, fb_width) / @intToFloat(f32, fb_height),
        0.01,
        200.0,
    );
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

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
                .depth_load_op = if (state.lol == 0) .clear else .load,
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
            pass.setIndexBuffer(ib_info.gpuobj.?, .uint16, 0, ib_info.size);

            pass.setPipeline(pipeline);

            {
                const mem = gctx.uniformsAllocate(FrameUniforms, 1);
                mem.slice[0].world_to_clip = zm.transpose(cam_world_to_clip);
                mem.slice[0].camera_position = state.camera.position;

                pass.setBindGroup(0, bind_group, &.{mem.offset});
            }

            for (state.drawables.items) |drawable| {
                // Update "object to world" xform.
                const object_to_world = zm.translationV(zm.load(drawable.position[0..], zm.Vec, 3));

                const mem = gctx.uniformsAllocate(DrawUniforms, 1);
                mem.slice[0].object_to_world = zm.transpose(object_to_world);
                mem.slice[0].basecolor_roughness = drawable.basecolor_roughness;

                pass.setBindGroup(1, bind_group, &.{mem.offset});

                // Draw.
                pass.drawIndexed(
                    state.meshes.items[drawable.mesh_index].num_indices,
                    1,
                    state.meshes.items[drawable.mesh_index].index_offset,
                    state.meshes.items[drawable.mesh_index].vertex_offset,
                    0,
                );
            }

            // while (iter.next()) |e| {
            //     e.pos.x += e.vel.x * iter.iter.delta_time;
            //     e.pos.y += e.vel.y * iter.iter.delta_time;
            //     e.pos.z += e.vel.z * iter.iter.delta_time;
            //     // std.debug.print("Move wrapped: p: {d}, v: {d} - {s}\n", .{ e.pos, e.vel, iter.entity().getName() });
            //     const object_to_world = zm.mul(zm.rotationY(t + state.lol), zm.translation(e.pos.x + state.lol, e.pos.y, e.pos.z));
            //     const object_to_clip = zm.mul(object_to_world, cam_world_to_clip);

            //     const mem = gctx.uniformsAllocate(zm.Mat, 1);
            //     mem.slice[0] = zm.transpose(object_to_clip);

            //     pass.setBindGroup(0, bind_group, &.{mem.offset});
            //     pass.drawIndexed(3, 1, 0, 0, 0);
            // }
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});
}
