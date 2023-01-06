const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const gfx = @import("../gfx_d3d12.zig");

const zbt = @import("zbullet");
const zm = @import("zmath");
const znoise = @import("znoise");
const zpool = @import("zpool");

const glfw = @import("glfw");

const zd3d12 = @import("zd3d12");
const zwin32 = @import("zwin32");
const w32 = zwin32.base;
const d3d12 = zwin32.d3d12;
const hrPanic = zwin32.hrPanic;

const fd = @import("../flecs_data.zig");
const config = @import("../config.zig");
const util = @import("../util.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const assert = std.debug.assert;

const IndexType = u32;
const patches_on_side = 5;
const patch_count = patches_on_side * patches_on_side;
const patch_side_vertex_count = config.patch_width;
const indices_per_patch: u32 = (config.patch_width - 1) * (config.patch_width - 1) * 6;
const vertices_per_patch: u32 = patch_side_vertex_count * patch_side_vertex_count;

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
};

// TODO: Figure out how to do interop to share this struct with HSLS.
const FrameUniforms = extern struct {
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

// TODO: Figure out how to do interop to share this struct with HSLS.
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
        generating_heights_setup,
        generating_heights,
        generating_normals_setup,
        generating_normals,
        generating_physics_setup,
        generating_physics,
        writing_physics,
        writing_gfx,
        loaded,
    } = .not_used,
    lod: enum {
        low,
        full,
    } = .full,
    pos: [2]i32 = undefined,
    lookup: u32 = undefined,
    index_offset: u32 = undefined,
    vertex_offset: i32 = undefined,
    hash: i32 = 0,
    heights: [config.patch_width * config.patch_width]f32,
    vertices: [patch_side_vertex_count * patch_side_vertex_count]Vertex,
    physics_shape: ?zbt.Shape,
    physics_body: zbt.Body,
    entity: flecs.EntityId,
};

const max_loaded_patches = 64;

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    physics_world: zbt.World,
    sys: flecs.EntityId,

    gfx: *gfx.D3D12State,
    pipeline: zd3d12.PipelineHandle,
    vertex_buffer: zd3d12.ResourceHandle,
    index_buffer: zd3d12.ResourceHandle,

    meshes: std.ArrayList(Mesh),

    indices: std.ArrayList(IndexType),
    patches: std.ArrayList(Patch),
    loading_patch: bool = false,

    query_camera: flecs.Query,
    query_lights: flecs.Query,
    query_loader: flecs.Query,
    noise: znoise.FnlGenerator,
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
        var z: u32 = 0;
        const width = @intCast(u32, config.patch_width);
        const height = @intCast(u32, config.patch_width);
        while (z < height - 1) : (z += 1) {
            var x: u32 = 0;
            while (x < width - 1) : (x += 1) {
                const indices_quad = [_]u32{
                    x + z * width, //           0
                    x + (z + 1) * width, //     4
                    x + 1 + z * width, //       1
                    x + 1 + (z + 1) * width, // 5
                };

                patch_indices[i + 0] = indices_quad[0]; // 0
                patch_indices[i + 1] = indices_quad[1]; // 4
                patch_indices[i + 2] = indices_quad[2]; // 1

                patch_indices[i + 3] = indices_quad[2]; // 1
                patch_indices[i + 4] = indices_quad[1]; // 4
                patch_indices[i + 5] = indices_quad[3]; // 5

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
        std.debug.assert(i == indices_per_patch);
        std.debug.assert(i == indices_per_patch);
        std.debug.assert(i == indices_per_patch);
        std.debug.assert(i == indices_per_patch);
    }

    std.debug.assert(patch_indices.len == indices_per_patch);

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

pub fn create(
    name: IdLocal,
    allocator: std.mem.Allocator,
    gfxstate: *gfx.D3D12State,
    flecs_world: *flecs.World,
    physics_world: zbt.World,
    noise: znoise.FnlGenerator,
) !*SystemState {
    std.log.debug("Creating terrain system", .{});
    var query_builder_camera = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_camera
        .withReadonly(fd.Camera)
        .withReadonly(fd.Position);
    var query_camera = query_builder_camera.buildQuery();

    var query_builder_lights = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_lights
        .with(fd.Light)
        .with(fd.Transform);
    var query_lights = query_builder_lights.buildQuery();

    var query_builder_loader = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_loader
        .with(fd.WorldLoader)
        .with(fd.Position);
    var query_loader = query_builder_loader.buildQuery();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var gctx = gfxstate.gctx;

    const pipeline = blk: {
        // TODO: Replace InputAssembly with vertex fetch in shader
        const input_layout_desc = [_]d3d12.INPUT_ELEMENT_DESC{
            d3d12.INPUT_ELEMENT_DESC.init("POSITION", 0, .R32G32B32_FLOAT, 0, 0, .PER_VERTEX_DATA, 0),
            d3d12.INPUT_ELEMENT_DESC.init("_Normal", 0, .R32G32B32_FLOAT, 0, @offsetOf(Vertex, "normal"), .PER_VERTEX_DATA, 0),
        };

        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        // TODO: Replace InputAssembly with vertex fetch in shader
        pso_desc.InputLayout = .{
            .pInputElementDescs = &input_layout_desc,
            .NumElements = input_layout_desc.len,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DSVFormat = .D32_FLOAT;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        break :blk gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/terrain.vs.cso",
            "shaders/terrain.ps.cso",
        );
    };

    var meshes = std.ArrayList(Mesh).init(allocator);
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_positions = std.ArrayList([3]f32).init(arena);
    var meshes_normals = std.ArrayList([3]f32).init(arena);
    initPatches(allocator, &meshes, &meshes_indices, &meshes_positions, &meshes_normals);

    const total_num_vertices = @intCast(u32, meshes_positions.items.len);
    const total_num_indices = @intCast(u32, meshes_indices.items.len);
    assert(total_num_indices == indices_per_patch * patch_count);

    const vertex_buffer = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &d3d12.RESOURCE_DESC.initBuffer(total_num_vertices * @sizeOf(Vertex)),
        d3d12.RESOURCE_STATE_COPY_DEST,
        null,
    ) catch |err| hrPanic(err);

    const index_buffer = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &d3d12.RESOURCE_DESC.initBuffer(total_num_indices * @sizeOf(IndexType)),
        d3d12.RESOURCE_STATE_COPY_DEST,
        null,
    ) catch |err| hrPanic(err);

    // Fill vertex buffer with vertex data.
    const verts = gctx.allocateUploadBufferRegion(Vertex, total_num_vertices);
    for (meshes_positions.items) |_, i| {
        verts.cpu_slice[i].position = meshes_positions.items[i];
        verts.cpu_slice[i].normal = meshes_normals.items[i];
    }

    gctx.cmdlist.CopyBufferRegion(
        gctx.lookupResource(vertex_buffer).?,
        0,
        verts.buffer,
        verts.buffer_offset,
        verts.cpu_slice.len * @sizeOf(@TypeOf(verts.cpu_slice[0])),
    );

    const indices = gctx.allocateUploadBufferRegion(IndexType, total_num_indices);
    for (meshes_indices.items) |_, i| {
        indices.cpu_slice[i] = meshes_indices.items[i];
    }

    // Fill index buffer with index data.
    gctx.cmdlist.CopyBufferRegion(
        gctx.lookupResource(index_buffer).?,
        0,
        indices.buffer,
        indices.buffer_offset,
        indices.cpu_slice.len * @sizeOf(@TypeOf(indices.cpu_slice[0])),
    );

    gctx.addTransitionBarrier(vertex_buffer, d3d12.RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER);
    gctx.addTransitionBarrier(index_buffer, d3d12.RESOURCE_STATE_INDEX_BUFFER);
    gctx.flushResourceBarriers();

    // State
    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .physics_world = physics_world,
        .sys = sys,

        .gfx = gfxstate,
        .pipeline = pipeline,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,

        .meshes = meshes,

        .patches = std.ArrayList(Patch).init(allocator),
        .indices = std.ArrayList(IndexType).init(allocator),
        // .bodies = std.ArrayList(zbt.Body).init(),
        .query_camera = query_camera,
        .query_lights = query_lights,
        .query_loader = query_loader,
        .noise = noise,
    };

    state.indices.appendSlice(meshes_indices.items[0..indices_per_patch]) catch unreachable;
    state.patches.resize(patch_count * 2) catch unreachable;
    for (state.patches.items) |*patch| {
        patch.status = .not_used;
        patch.hash = std.math.maxInt(i32);
        patch.physics_shape = null;
        //patch.lookup = @intCast(u32, i);
        // patch.index_offset = @intCast(u32, i) * indices_per_patch;
        // patch.vertex_offset = @intCast(i32, i * vertices_per_patch);
    }
    // flecs_world.observer(ObserverCallback, .on_set, state);

    return state;
}

pub fn destroy(state: *SystemState) void {
    // state.comp_query.deinit();
    state.query_camera.deinit();
    state.query_lights.deinit();
    state.query_loader.deinit();
    state.meshes.deinit();
    state.allocator.destroy(state);
}

//      ██╗ ██████╗ ██████╗ ███████╗
//      ██║██╔═══██╗██╔══██╗██╔════╝
//      ██║██║   ██║██████╔╝███████╗
// ██   ██║██║   ██║██╔══██╗╚════██║
// ╚█████╔╝╚██████╔╝██████╔╝███████║
//  ╚════╝  ╚═════╝ ╚═════╝ ╚══════╝

const ThreadContextGenerateHeights = struct {
    patch: *Patch,
    state: *SystemState,
};

fn jobGenerateHeights(ctx: ThreadContextGenerateHeights) !void {
    var patch = ctx.patch;
    var state = ctx.state;
    var z: f32 = 0;
    while (z < config.patch_width) : (z += 1) {
        var x: f32 = 0;
        while (x < config.patch_width) : (x += 1) {
            const world_x = @intToFloat(f32, patch.pos[0]) + x;
            const world_z = @intToFloat(f32, patch.pos[1]) + z;
            const height = util.heightAtXZ(world_x, world_z, config.noise_scale_xz, config.noise_scale_y, config.noise_offset_y, &state.noise);
            const index = @floatToInt(u32, x) + @floatToInt(u32, z) * config.patch_width;
            patch.heights[index] = height;
        }
    }
    patch.status = .generating_normals_setup;
}

// fn jobGenerateHeights(ctx: ThreadContextGenerateHeights) !void {
//     _ = ctx;
//     // ctx.patch.
//     var patch = ctx.patch;
//     // var state = ctx.state;
//     var z: f32 = 0;
//     while (z < config.patch_width) : (z += 1) {
//         var x: f32 = 0;
//         while (x < config.patch_width) : (x += 1) {
//             // const height = switch (patch.lookup % 6) {
//             //     0 => blk: {
//             //         break :blk x * 0.1;
//             //     },
//             //     1 => blk: {
//             //         break :blk z * 0.1;
//             //     },
//             //     2 => blk: {
//             //         break :blk x + z;
//             //     },
//             //     3 => blk: {
//             //         break :blk x - z;
//             //     },
//             //     4 => blk: {
//             //         break :blk -x - z;
//             //     },
//             //     5 => blk: {
//             //         break :blk 0;
//             //     },
//             //     else => {
//             //         unreachable;
//             //     },
//             // };
//             const height = std.math.min(x, z);
//             // const world_x = @intToFloat(f32, patch.pos[0]) + x;
//             // const world_z = @intToFloat(f32, patch.pos[1]) + z;
//             // const height = config.noise_scale_y * (config.noise_offset_y + state.noise.noise2(world_x * config.noise_scale_xz, world_z * config.noise_scale_xz));
//             const index = @floatToInt(u32, x) + @floatToInt(u32, z) * config.patch_width;
//             patch.heights[index] = height;
//         }
//     }
//     patch.status = .generating_normals_setup;
// }

const ThreadContextGenerateShape = struct {
    patch: *Patch,
    state: *SystemState,
};

fn jobGenerateShape(ctx: ThreadContextGenerateShape) !void {
    var patch = ctx.patch;
    var state = ctx.state;

    const trimesh = zbt.initTriangleMeshShape();
    trimesh.addIndexVertexArray(
        @intCast(u32, indices_per_patch / 3),
        state.indices.items.ptr,
        @sizeOf([3]u32),
        @intCast(u32, patch.vertices[0..].len),
        &patch.vertices[0],
        @sizeOf(Vertex),
    );
    trimesh.finish();

    const shape = trimesh.asShape();
    patch.physics_shape = shape;
    patch.status = .writing_physics;
}

const ThreadContextGenerateNormals = struct {
    patch: *Patch,
    state: *SystemState,
};

fn jobGenerateNormals(ctx: ThreadContextGenerateNormals) !void {
    var patch = ctx.patch;
    const heights = patch.heights;
    // var state = ctx.state;

    var z: i32 = 0;
    while (z < config.patch_width) : (z += 1) {
        var x: i32 = 0;
        while (x < config.patch_width) : (x += 1) {
            // const world_x = @intToFloat(f32, patch.pos[0] + x);
            // const world_z = @intToFloat(f32, patch.pos[1] + z);
            const index = @intCast(u32, x + z * config.patch_width);
            const height = heights[index];

            patch.vertices[index].position[0] = @intToFloat(f32, x);
            patch.vertices[index].position[1] = height;
            patch.vertices[index].position[2] = @intToFloat(f32, z);
            patch.vertices[index].normal[0] = 0;
            patch.vertices[index].normal[1] = 1;
            patch.vertices[index].normal[2] = 0;

            // const height_l = config.noise_scale_y * (config.noise_offset_y + state.noise.noise2((world_x - 1) * config.noise_scale_xz, world_z * config.noise_scale_xz));
            // const height_r = config.noise_scale_y * (config.noise_offset_y + state.noise.noise2((world_x + 1) * config.noise_scale_xz, world_z * config.noise_scale_xz));
            // const height_u = config.noise_scale_y * (config.noise_offset_y + state.noise.noise2(world_x * config.noise_scale_xz, (world_z - 1) * config.noise_scale_xz));
            // const height_d = config.noise_scale_y * (config.noise_offset_y + state.noise.noise2(world_x * config.noise_scale_xz, (world_z + 1) * config.noise_scale_xz));
            if (0 < x and x < config.patch_width - 1 and 0 < z and z < config.patch_width - 1) {
                const index_l = @intCast(u32, x - 1 + z * config.patch_width);
                const index_r = @intCast(u32, x + 1 + z * config.patch_width);
                const index_u = @intCast(u32, x + (z + 1) * config.patch_width);
                const index_d = @intCast(u32, x + (z - 1) * config.patch_width);
                const height_l = heights[index_l];
                const height_r = heights[index_r];
                const height_u = heights[index_u];
                const height_d = heights[index_d];
                const dx = 0.5 * (height_r - height_l);
                const dz = 0.5 * (height_u - height_d);
                const ux = zm.Vec{ 1, dx, 0, 0 };
                const uz = zm.Vec{ 0, dz, 1, 0 };
                const cross = zm.cross3(zm.normalize3(ux), zm.normalize3(uz));
                const normal = zm.normalize3(cross) * zm.f32x4s(-1.0);
                patch.vertices[index].normal = zm.vecToArr3(normal);
                // patch.vertices[index].normal[0] *= -1;
                //patch.vertices[index].normal[2] *= -1;
            }
        }
    }
    patch.status = .generating_physics_setup;
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    _ = state.physics_world.stepSimulation(iter.iter.delta_time, .{});

    var entity_iter = state.query_loader.iterator(struct {
        loader: *fd.WorldLoader,
        position: *fd.Position,
    });

    while (entity_iter.next()) |comps| {
        if (state.loading_patch) {
            // break;
        }

        // TODO: Rewrite this to be smart and fast instead of slow and dumb? :D

        var free_lookup: u32 = 0;
        while (free_lookup < patch_count) : (free_lookup += 1) {
            for (state.patches.items) |*patch| {
                if (patch.status != .not_used and patch.lookup == free_lookup) {
                    break;
                }
            } else {
                break;
            }
        }

        const comp_pos_i_x = @floatToInt(i32, comps.position.x);
        const comp_pos_i_z = @floatToInt(i32, comps.position.z);
        var range: i32 = 0;
        comp_loop: while (range < comps.loader.range) : (range += 1) {
            var x: i32 = -range;
            while (x <= range) : (x += 1) {
                var z: i32 = -range;
                z_loop: while (z <= range) : (z += 1) {
                    const world_x = @divFloor(comp_pos_i_x, config.patch_width) * config.patch_width + x * config.patch_width;
                    const world_z = @divFloor(comp_pos_i_z, config.patch_width) * config.patch_width + z * config.patch_width;
                    const patch_hash = @divTrunc(world_x, config.patch_width) + 1024 * @divTrunc(world_z, config.patch_width);

                    for (state.patches.items) |*patch| {
                        if (patch.hash == patch_hash) {
                            continue :z_loop;
                        }
                    }

                    var free_patch: ?*Patch = null;
                    if (free_lookup == patch_count) {
                        var unload_patch = &state.patches.items[0];
                        var dist_best: i32 = -1; //(unload_patch.pos[0] - comp_pos_i_x) + (unload_patch.pos[1] - comp_pos_i_z);
                        for (state.patches.items) |*patch| {
                            if (patch.status == .not_used) {
                                continue;
                            }

                            var distX = math.absInt(patch.pos[0] - comp_pos_i_x) catch unreachable;
                            var distZ = math.absInt(patch.pos[1] - comp_pos_i_z) catch unreachable;
                            const dist = distX + distZ;
                            if (dist <= dist_best) {
                                continue;
                            }

                            dist_best = dist;
                            unload_patch = patch;
                        }

                        if (unload_patch.status != .loaded) {
                            state.loading_patch = false;
                        }

                        if (unload_patch.physics_shape != null) {
                            state.physics_world.removeBody(unload_patch.physics_body);
                            unload_patch.physics_shape.?.deinit();
                            unload_patch.physics_shape = null;
                        }

                        state.flecs_world.delete(unload_patch.entity);
                        unload_patch.entity = 0;

                        free_lookup = unload_patch.lookup;
                        unload_patch.status = .not_used;
                        free_patch = unload_patch;
                        // unload_patch.hash = std.math.maxInt(i32);
                    }

                    if (free_patch == null) {
                        for (state.patches.items) |*patch| {
                            if (patch.status != .not_used) {
                                continue;
                            }

                            free_patch = patch;
                            break;

                            // patch.hash = patch_hash;
                            // patch.pos = [_]i32{ world_x, world_z };
                            // patch.status = .in_queue;
                            // patch.lookup = free_lookup;
                            // state.loading_patch = true;
                            // break :comp_loop;
                        }
                    }

                    free_patch.?.hash = patch_hash;
                    free_patch.?.pos = [_]i32{ world_x, world_z };
                    free_patch.?.status = .in_queue;
                    free_patch.?.lookup = free_lookup;
                    free_patch.?.index_offset = @intCast(u32, free_lookup) * indices_per_patch;
                    free_patch.?.vertex_offset = @intCast(i32, free_lookup * vertices_per_patch);
                    state.loading_patch = true;
                    std.debug.print("free_patch {} h{} x{} z{}\n", .{ free_patch.?.lookup, free_patch.?.hash, free_patch.?.pos[0], free_patch.?.pos[1] });
                    break :comp_loop;
                }
            }
        }
    }

    for (state.patches.items) |*patch| {
        // LOL @ thread safety 😂😂😂
        patch.status =
            switch (patch.status) {
            .not_used => continue,
            .in_queue => blk: {
                break :blk .generating_heights_setup;
            },
            .generating_heights_setup => blk: {
                const thread_config = .{};
                var thread_args: ThreadContextGenerateHeights = .{ .patch = patch, .state = state };
                const thread = std.Thread.spawn(thread_config, jobGenerateHeights, .{thread_args}) catch unreachable;
                thread.setName("generating_heights") catch {};
                thread.detach();
                // _ = thread;
                std.debug.print("generating_heights_setup {} h{} x{} z{}\n", .{ patch.lookup, patch.hash, patch.pos[0], patch.pos[1] });

                break :blk .generating_heights;
            },
            .generating_heights => blk: {
                break :blk .generating_heights;
            },
            .generating_normals_setup => blk: {
                const thread_config = .{};
                var thread_args: ThreadContextGenerateNormals = .{ .patch = patch, .state = state };
                const thread = std.Thread.spawn(thread_config, jobGenerateNormals, .{thread_args}) catch unreachable;
                thread.setName("generating_normals") catch {};
                thread.detach();
                // _ = thread;
                break :blk .generating_normals;
            },
            .generating_normals => blk: {
                break :blk .generating_normals;
            },
            .generating_physics_setup => blk: {
                const thread_config = .{};
                var thread_args: ThreadContextGenerateShape = .{ .patch = patch, .state = state };
                const thread = std.Thread.spawn(thread_config, jobGenerateShape, .{thread_args}) catch unreachable;
                thread.setName("generating_physics") catch {};
                thread.detach();
                // _ = thread;
                std.debug.print("generating_physics_setup {} h{} x{} z{}\n", .{ patch.lookup, patch.hash, patch.pos[0], patch.pos[1] });
                break :blk .generating_physics;
            },
            .generating_physics => blk: {
                break :blk .generating_physics;
            },
            .writing_physics => blk: {
                const transform = [_]f32{
                    1.0,                            0.0, 0.0,
                    0.0,                            1.0, 0.0,
                    0.0,                            0.0, 1.0,
                    @intToFloat(f32, patch.pos[0]), 0,   @intToFloat(f32, patch.pos[1]),
                };

                const body = zbt.initBody(
                    0,
                    &transform,
                    patch.physics_shape.?,
                );

                body.setDamping(0.1, 0.1);
                body.setRestitution(0.5);
                body.setFriction(0.2);
                patch.physics_body = body;

                state.physics_world.addBody(body);

                break :blk .writing_gfx;
            },
            .writing_gfx => blk: {
                std.debug.print("patch {} h{} x{} z{}\n", .{ patch.lookup, patch.hash, patch.pos[0], patch.pos[1] });

                // Upload patch vertices to vertex buffer
                {
                    var gctx = state.gfx.gctx;

                    gctx.addTransitionBarrier(state.vertex_buffer, d3d12.RESOURCE_STATE_COPY_DEST);
                    gctx.flushResourceBarriers();

                    const verts = gctx.allocateUploadBufferRegion(Vertex, patch.vertices.len);
                    for (patch.vertices) |_, i| {
                        verts.cpu_slice[i].position = patch.vertices[i].position;
                        verts.cpu_slice[i].normal = patch.vertices[i].normal;
                    }

                    gctx.cmdlist.CopyBufferRegion(
                        gctx.lookupResource(state.vertex_buffer).?,
                        patch.lookup * config.patch_width * config.patch_width * @sizeOf(Vertex),
                        verts.buffer,
                        verts.buffer_offset,
                        verts.cpu_slice.len * @sizeOf(@TypeOf(verts.cpu_slice[0])),
                    );

                    gctx.addTransitionBarrier(state.vertex_buffer, d3d12.RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER);
                    gctx.flushResourceBarriers();
                }

                var rand1 = std.rand.DefaultPrng.init(patch.lookup);
                var rand = rand1.random();
                var z: f32 = 0;
                while (z < config.patch_width) : (z += 8) {
                    var x: f32 = 0;
                    while (x < config.patch_width) : (x += 8) {
                        const world_x = @intToFloat(f32, patch.pos[0]) + x + rand.float(f32) * 10;
                        const world_z = @intToFloat(f32, patch.pos[1]) + z + rand.float(f32) * 10;
                        const height = util.heightAtXZ(world_x, world_z, config.noise_scale_xz, config.noise_scale_y, config.noise_offset_y, &state.noise);
                        if (height > 10 and height < 300) {
                            const noise = state.noise.noise2((world_x + 1000) * 4, (world_z + 1000) * 4);
                            if (noise > -0.1) {
                                const trunk_pos = fd.Position.init(world_x, height, world_z);
                                const trunk_scale = fd.Scale.create(0.4 + rand.float(f32) * 0.1, 3.0, 0.4 + rand.float(f32) * 0.1);
                                var trunk_transform: fd.Transform = undefined;
                                const z_trunk_scale_matrix = zm.scaling(trunk_scale.x, trunk_scale.y, trunk_scale.z);
                                const z_trunk_translate_matrix = zm.translation(trunk_pos.x, trunk_pos.y, trunk_pos.z);
                                const z_trunk_st_matrix = zm.mul(z_trunk_scale_matrix, z_trunk_translate_matrix);
                                zm.storeMat43(trunk_transform.matrix[0..], z_trunk_st_matrix);

                                var tree_trunk_ent = state.flecs_world.newEntity();
                                tree_trunk_ent.set(trunk_transform);
                                tree_trunk_ent.set(trunk_pos);
                                tree_trunk_ent.set(trunk_scale);
                                tree_trunk_ent.set(fd.CIShapeMeshInstance{
                                    .id = IdLocal.id64("tree_trunk"),
                                    .basecolor_roughness = .{ .r = 0.6, .g = 0.6, .b = 0.1, .roughness = 1.0 },
                                });

                                // CROWN
                                const crown_pos = fd.Position.init(world_x, height + 0.5 + rand.float(f32) * 2, world_z);
                                const crown_scale = fd.Scale.create(1.0 + rand.float(f32) * 0.3, 4.0 + rand.float(f32) * 8, 1.0 + rand.float(f32) * 0.3);
                                var crown_transform: fd.Transform = undefined;
                                const z_crown_scale_matrix = zm.scaling(crown_scale.x, crown_scale.y, crown_scale.z);
                                const z_crown_translate_matrix = zm.translation(crown_pos.x, crown_pos.y, crown_pos.z);
                                const z_crown_st_matrix = zm.mul(z_crown_scale_matrix, z_crown_translate_matrix);
                                zm.storeMat43(crown_transform.matrix[0..], z_crown_st_matrix);

                                var tree_crown_ent = state.flecs_world.newEntity();
                                tree_crown_ent.set(crown_transform);
                                tree_crown_ent.set(crown_pos);
                                tree_crown_ent.set(fd.EulerRotation.init(0, 0, 0));
                                tree_crown_ent.set(crown_scale);
                                tree_crown_ent.set(fd.CIShapeMeshInstance{
                                    .id = IdLocal.id64("tree_crown"),
                                    .basecolor_roughness = .{ .r = rand.float(f32) * 0.3, .g = 0.6 + rand.float(f32) * 0.4, .b = rand.float(f32) * 0.2, .roughness = 0.8 },
                                });

                                // if (rand.boolean()) {
                                //     const crown_pos2 = zm.translation(world_x, height + 2 + rand.float(f32), world_z);
                                //     var crown_transform2: fd.Transform = undefined;
                                //     zm.storeMat43(crown_transform2.matrix[0..], crown_pos2);
                                //     var tree_crown_ent2 = state.flecs_world.newEntity();
                                //     tree_crown_ent2.set(crown_transform2);
                                //     tree_crown_ent2.set(fd.Scale.create(1.0 + rand.float(f32) * 0.3, 4.0 + rand.float(f32) * 4, 1.0 + rand.float(f32) * 0.3));
                                //     tree_crown_ent2.set(fd.CIShapeMeshInstance{
                                //         .id = IdLocal.id64("tree_crown"),
                                //         .basecolor_roughness = .{ .r = 0.2, .g = 1.0, .b = 0.2, .roughness = 0.2 },
                                //     });
                                // }
                            }
                        }
                    }
                }

                state.loading_patch = false;
                break :blk .loaded;
            },
            .loaded => blk: {
                const patch_ent = state.flecs_world.newEntity();
                patch_ent.set(fd.Position{ .x = @intToFloat(f32, patch.pos[0]), .y = 0, .z = @intToFloat(f32, patch.pos[1]) });
                patch_ent.set(fd.WorldPatch{ .lookup = patch.lookup });
                patch.entity = patch_ent.id;

                break :blk .loaded;
            },
        };
    }

    const CameraQueryComps = struct {
        cam: *const fd.Camera,
        pos: *const fd.Position,
    };
    var entity_iter_camera = state.query_camera.iterator(CameraQueryComps);
    var camera_comps: ?CameraQueryComps = null;
    while (entity_iter_camera.next()) |comps| {
        if (comps.cam.active) {
            camera_comps = comps;
            break;
        }
    }

    if (camera_comps == null) {
        return;
    }

    // D3D12
    var gctx = state.gfx.gctx;
    // Set input assembler (IA) state.
    gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
    const vertex_buffer_resource = gctx.lookupResource(state.vertex_buffer);
    gctx.cmdlist.IASetVertexBuffers(0, 1, &[_]d3d12.VERTEX_BUFFER_VIEW{.{
        .BufferLocation = vertex_buffer_resource.?.GetGPUVirtualAddress(),
        .SizeInBytes = @intCast(c_uint, vertex_buffer_resource.?.GetDesc().Width),
        .StrideInBytes = @sizeOf(Vertex),
    }});
    const index_buffer_resource = gctx.lookupResource(state.index_buffer);
    gctx.cmdlist.IASetIndexBuffer(&.{
        .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
        .SizeInBytes = @intCast(c_uint, index_buffer_resource.?.GetDesc().Width),
        .Format = .R32_UINT, // TODO: Check index format first
    });

    gctx.setCurrentPipeline(state.pipeline);

    // Upload per-frame constant data.
    {
        const cam = camera_comps.?.cam;
        const cam_world_to_clip = zm.loadMat(cam.world_to_clip[0..]);

        const mem = gctx.allocateUploadMemory(FrameUniforms, 1);
        mem.cpu_slice[0].world_to_clip = zm.transpose(cam_world_to_clip);
        mem.cpu_slice[0].camera_position = camera_comps.?.pos.elemsConst().*;
        mem.cpu_slice[0].time = @floatCast(f32, state.gfx.stats.time);
        mem.cpu_slice[0].light_count = 0;

        var entity_iter_lights = state.query_lights.iterator(struct {
            light: *fd.Light,
            transform: *fd.Transform,
        });

        var light_i: u32 = 0;
        while (entity_iter_lights.next()) |comps| {
            const light_pos = comps.transform.getPos00();
            std.mem.copy(f32, mem.cpu_slice[0].light_positions[light_i][0..], light_pos[0..]);
            std.mem.copy(f32, mem.cpu_slice[0].light_radiances[light_i][0..3], comps.light.radiance.elemsConst().*[0..]);
            mem.cpu_slice[0].light_radiances[light_i][3] = comps.light.range;
            // std.debug.print("light: {any}{any}\n", .{ light_i, mem.slice[0].light_positions[light_i] });

            light_i += 1;
        }
        mem.cpu_slice[0].light_count = light_i;

        gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
    }

    for (state.patches.items) |*patch| {
        if (patch.status == .loaded) {
            // const scale_matrix = zm.scaling(comps.scale.x, comps.scale.y, comps.scale.z);
            // const transform = zm.loadMat43(comps.transform.matrix[0..]);
            // const object_to_world = zm.mul(scale_matrix, transform);
            const posmat = zm.translation(
                @intToFloat(f32, patch.pos[0]),
                @intToFloat(f32, 0),
                @intToFloat(f32, patch.pos[1]),
            );
            // const object_to_world = zm.loadMat43(comps.transform.matrix[0..]);

            const mem = gctx.allocateUploadMemory(DrawUniforms, 1);
            mem.cpu_slice[0].object_to_world = zm.transpose(posmat);
            mem.cpu_slice[0].basecolor_roughness[0] = 1;
            mem.cpu_slice[0].basecolor_roughness[1] = 1;
            mem.cpu_slice[0].basecolor_roughness[2] = 0;
            mem.cpu_slice[0].basecolor_roughness[3] = 1;
            gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

            // Draw.
            // var vertices_per_patch: u32 = patch_side_vertex_count * patch_side_vertex_count;
            gctx.cmdlist.DrawIndexedInstanced(indices_per_patch, 1, patch.index_offset, patch.vertex_offset, 0);
        }
    }
}
