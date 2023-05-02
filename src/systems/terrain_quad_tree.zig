const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const assert = std.debug.assert;
const math = std.math;

const zm = @import("zmath");
const zmu = @import("zmathutil");
const flecs = @import("flecs");

const config = @import("../config.zig");
const gfx = @import("../gfx_d3d12.zig");
const zd3d12 = @import("zd3d12");
const zwin32 = @import("zwin32");
const w32 = zwin32.w32;
const dxgi = zwin32.dxgi;
const wic = zwin32.wic;
const hrPanic = zwin32.hrPanic;
const hrPanicOnFail = zwin32.hrPanicOnFail;
const d3d12 = zwin32.d3d12;
const dds_loader = zwin32.dds_loader;

const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const tides_math = @import("../core/math.zig");

const IndexType = @import("../renderer/renderer_types.zig").IndexType;
const Vertex = @import("../renderer/renderer_types.zig").Vertex;
const Mesh = @import("../renderer/renderer_types.zig").Mesh;
const mesh_loader = @import("../renderer/mesh_loader.zig");

const lod_load_range = 300;

const TerrainLayer = struct {
    diffuse: gfx.TextureHandle,
    normal: gfx.TextureHandle,
    arm: gfx.TextureHandle,
};

const TerrainLayerTextureIndices = extern struct {
    diffuse_index: u32,
    normal_index: u32,
    arm_index: u32,
    padding: u32,
};

const FrameUniforms = extern struct {
    world_to_clip: zm.Mat,
    camera_position: [3]f32,
    time: f32,
    noise_offset_y: f32,
    noise_scale_y: f32,
    padding3: u32,
    light_count: u32,
    light_positions: [32][4]f32,
    light_radiances: [32][4]f32,
};

const SceneUniforms = extern struct {
    radiance_texture_index: u32,
    irradiance_texture_index: u32,
    brdf_integration_texture_index: u32,
};

const DrawUniforms = struct {
    start_instance_location: u32,
    vertex_offset: i32,
    vertex_buffer_index: u32,
    instance_data_buffer_index: u32,
    terrain_layers_buffer_index: u32,
};

const InstanceData = struct {
    object_to_world: zm.Mat,
    heightmap_index: u32,
    splatmap_index: u32,
    padding1: u32,
    padding2: u32,
};

const max_instances = 100;
const max_instances_per_draw_call = 20;

const DrawCall = struct {
    mesh_index: u32,
    index_count: u32,
    instance_count: u32,
    index_offset: u32,
    vertex_offset: i32,
    start_instance_location: u32,
};

const invalid_index = std.math.maxInt(u32);
const QuadTreeNode = struct {
    center: [2]f32,
    size: [2]f32,
    child_indices: [4]u32,
    mesh_lod: u32,
    patch_index: [2]u32,
    // TODO(gmodarelli): Do not store these here when we implement streaming
    heightmap_handle: ?gfx.TextureHandle,
    splatmap_handle: ?gfx.TextureHandle,

    pub inline fn containsPoint(self: *QuadTreeNode, point: [2]f32) bool {
        return (point[0] > (self.center[0] - self.size[0]) and
            point[0] < (self.center[0] + self.size[0]) and
            point[1] > (self.center[1] - self.size[1]) and
            point[1] < (self.center[1] + self.size[1]));
    }

    pub inline fn nearPoint(self: *QuadTreeNode, point: [2]f32, range: f32) bool {
        const half_size = self.size[0] / 2;
        const circle_distance_x = @fabs(point[0] - self.center[0]);
        const circle_distance_y = @fabs(point[1] - self.center[1]);

        if (circle_distance_x > (half_size + range)) {
            return false;
        }
        if (circle_distance_y > (half_size + range)) {
            return false;
        }

        if (circle_distance_x <= (half_size)) {
            return true;
        }
        if (circle_distance_y <= (half_size)) {
            return true;
        }

        const corner_distance_sq = (circle_distance_x - half_size) * (circle_distance_x - half_size) +
            (circle_distance_y - half_size) * (circle_distance_y - half_size);

        return (corner_distance_sq <= (range * range));
    }

    pub inline fn isLoaded(self: *QuadTreeNode) bool {
        return self.heightmap_handle != null and self.splatmap_handle != null;
    }

    pub fn containedInsideChildren(self: *QuadTreeNode, point: [2]f32, range: f32, nodes: *std.ArrayList(QuadTreeNode)) bool {
        if (!self.nearPoint(point, range)) {
            return false;
        }

        for (self.child_indices) |child_index| {
            if (child_index == std.math.maxInt(u32)) {
                return false;
            }

            var node = nodes.items[child_index];
            if (node.nearPoint(point, range)) {
                return true;
            }
        }

        return false;
    }

    pub fn areChildrenLoaded(self: *QuadTreeNode, nodes: *std.ArrayList(QuadTreeNode)) bool {
        if (!self.isLoaded()) {
            return false;
        }

        for (self.child_indices) |child_index| {
            if (child_index == std.math.maxInt(u32)) {
                return false;
            }

            var node = nodes.items[child_index];
            if (!node.isLoaded()) {
                return false;
            }
        }

        return true;
    }
};

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    sys: flecs.EntityId,

    gfx: *gfx.D3D12State,

    query_camera: flecs.Query,
    query_lights: flecs.Query,

    vertex_buffer: gfx.BufferHandle,
    index_buffer: gfx.BufferHandle,
    terrain_layers_buffer: gfx.BufferHandle,
    instance_data_buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle,
    instance_data: std.ArrayList(InstanceData),
    draw_calls: std.ArrayList(DrawCall),
    gpu_frame_profiler_index: u64 = undefined,

    // NOTE(gmodarelli): This should be part of gfx_d3d12.zig or texture.zig
    // but for now it's here to speed test it out and speed things along
    textures_heap: *d3d12.IHeap,
    textures_heap_offset: u64 = 0,

    terrain_quad_tree_nodes: std.ArrayList(QuadTreeNode),
    terrain_lod_meshes: std.ArrayList(Mesh),
    quads_to_render: std.ArrayList(u32),
    quads_to_load: std.ArrayList(u32),

    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
    splatmap_patch_type_id: world_patch_manager.PatchTypeId,

    cam_pos_old: [3]f32 = .{ -100000, 0, -100000 }, // NOTE(Anders): Assumes only one camera
};

fn loadMesh(
    allocator: std.mem.Allocator,
    path: []const u8,
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) !void {
    const mesh = mesh_loader.loadObjMeshFromFile(allocator, path, meshes_indices, meshes_vertices) catch unreachable;
    meshes.append(mesh) catch unreachable;
}

// TODO(gmodarelli): Remove this function once we add splatmaps to the patch manager or
// once we add load/create function variants to zd3d12
// NOTE(gmodarelli): The caller must release the IFormatConverter
// eg. image_conv.Release();
fn loadTexture(gctx: *zd3d12.GraphicsContext, path: []const u8) !struct {
    image: *wic.IFormatConverter,
    format: dxgi.FORMAT,
} {
    var path_u16: [300]u16 = undefined;
    assert(path.len < path_u16.len - 1);
    const path_len = std.unicode.utf8ToUtf16Le(path_u16[0..], path) catch unreachable;
    path_u16[path_len] = 0;

    const bmp_decoder = blk: {
        var maybe_bmp_decoder: ?*wic.IBitmapDecoder = undefined;
        hrPanicOnFail(gctx.wic_factory.CreateDecoderFromFilename(
            @ptrCast(w32.LPCWSTR, &path_u16),
            null,
            w32.GENERIC_READ,
            .MetadataCacheOnDemand,
            &maybe_bmp_decoder,
        ));
        break :blk maybe_bmp_decoder.?;
    };
    defer _ = bmp_decoder.Release();

    const bmp_frame = blk: {
        var maybe_bmp_frame: ?*wic.IBitmapFrameDecode = null;
        hrPanicOnFail(bmp_decoder.GetFrame(0, &maybe_bmp_frame));
        break :blk maybe_bmp_frame.?;
    };
    defer _ = bmp_frame.Release();

    const pixel_format = blk: {
        var pixel_format: w32.GUID = undefined;
        hrPanicOnFail(bmp_frame.GetPixelFormat(&pixel_format));
        break :blk pixel_format;
    };

    const eql = std.mem.eql;
    const asBytes = std.mem.asBytes;
    const num_components: u32 = blk: {
        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat24bppRGB))) break :blk 4;
        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat32bppRGB))) break :blk 4;
        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat32bppRGBA))) break :blk 4;
        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat32bppPRGBA))) break :blk 4;

        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat24bppBGR))) break :blk 4;
        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat32bppBGR))) break :blk 4;
        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat32bppBGRA))) break :blk 4;
        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat32bppPBGRA))) break :blk 4;
        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat64bppRGBA))) break :blk 4;

        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat8bppGray))) break :blk 1;
        if (eql(u8, asBytes(&pixel_format), asBytes(&wic.GUID_PixelFormat8bppAlpha))) break :blk 1;

        unreachable;
    };

    const wic_format = if (num_components == 1)
        &wic.GUID_PixelFormat8bppGray
    else
        &wic.GUID_PixelFormat32bppRGBA;

    const dxgi_format = if (num_components == 1) dxgi.FORMAT.R8_UNORM else dxgi.FORMAT.R8G8B8A8_UNORM;

    const image_conv = blk: {
        var maybe_image_conv: ?*wic.IFormatConverter = null;
        hrPanicOnFail(gctx.wic_factory.CreateFormatConverter(&maybe_image_conv));
        break :blk maybe_image_conv.?;
    };

    hrPanicOnFail(image_conv.Initialize(
        @ptrCast(*wic.IBitmapSource, bmp_frame),
        wic_format,
        .None,
        null,
        0.0,
        .Custom,
    ));

    return .{ .image = image_conv, .format = dxgi_format };
}

// TODO(gmodarelli): Add mip count, array size and resource dimension
// TODO(gmodarelli): Move to texture.zig when we need this in other systems
const TextureDesc = struct {
    width: u32,
    height: u32,
    format: dxgi.FORMAT,
    data: []u8,
};

fn createTextureFromPixelBuffer(
    texture_desc: TextureDesc,
    gfxstate: *gfx.D3D12State,
    heap: *d3d12.IHeap,
    heap_offset: *u64,
    in_frame: bool,
) !gfx.Texture {
    if (!in_frame) {
        // NOTE:(gmodarelli) If I schedule all of these uploads in a single frame I end up with all the textures
        // having the data from the first uploaded texture :(
        gfxstate.gctx.beginFrame();
    }

    const bpp = texture_desc.format.pixelSizeInBits();
    const row_bytes = @divFloor(@intCast(u64, texture_desc.width) * bpp + 7, 8); // round up to nearest byte
    const num_bytes = row_bytes * texture_desc.height;

    const subresource = d3d12.SUBRESOURCE_DATA{
        .pData = @ptrCast([*]u8, texture_desc.data[0..]),
        .RowPitch = @intCast(c_uint, row_bytes),
        .SlicePitch = @intCast(c_uint, num_bytes),
    };
    var subresources = [1]d3d12.SUBRESOURCE_DATA{subresource};

    // Create a texture and upload all its subresources to the GPU
    const resource = blk: {
        // Reserve space for the texture (subresources) from a pre-allocated HEAP
        var resource = allocateTextureMemory(
            gfxstate,
            heap,
            heap_offset,
            texture_desc.width,
            texture_desc.height,
            texture_desc.format,
            1,
        ) catch unreachable;

        // TODO(gmodarelli): Set a debug name
        // {
        //     var path_u16: [300]u16 = undefined;
        //     assert(path.len < path_u16.len - 1);
        //     const path_len = std.unicode.utf8ToUtf16Le(path_u16[0..], path) catch unreachable;
        //     path_u16[path_len] = 0;
        //     _ = resource.SetName(@ptrCast(w32.LPCWSTR, &path_u16));
        // }

        // Upload all subresources
        uploadSubResources(gfxstate, resource, &subresources, d3d12.RESOURCE_STATES.GENERIC_READ);

        break :blk resource;
    };

    if (!in_frame) {
        // NOTE(gmodarelli): If I schedule all of these uploads in a single frame I end up with all the textures
        // having the data from the first uploaded texture :(
        gfxstate.gctx.endFrame();
        gfxstate.gctx.finishGpuCommands();
    }

    // Create a persisten SRV descriptor for the texture
    const srv_allocation = gfxstate.gctx.allocatePersistentGpuDescriptors(1);
    gfxstate.gctx.device.CreateShaderResourceView(
        resource,
        null,
        srv_allocation.cpu_handle,
    );

    return gfx.Texture{
        .resource = resource,
        .persistent_descriptor = srv_allocation,
    };
}

fn createDDSTextureFromFile(
    path: []const u8,
    arena: std.mem.Allocator,
    gfxstate: *gfx.D3D12State,
    heap: *d3d12.IHeap,
    heap_offset: *u64,
    in_frame: bool,
) !gfx.Texture {
    // Generate Path
    std.log.debug("Creating texture from DDS {s}", .{path});

    if (!in_frame) {
        // NOTE:(gmodarelli) If I schedule all of these uploads in a single frame I end up with all the textures
        // having the data from the first uploaded texture :(
        gfxstate.gctx.beginFrame();
    }

    // Load DDS data into D3D12_SUBRESOURCE_DATA
    var subresources = std.ArrayList(d3d12.SUBRESOURCE_DATA).init(arena);
    const dds_info = dds_loader.loadTextureFromFile(path, arena, gfxstate.gctx.device, 0, &subresources) catch unreachable;

    // Create a texture and upload all its subresources to the GPU
    const resource = blk: {
        // Reserve space for the texture (subresources) from a pre-allocated HEAP
        var resource = allocateTextureMemory(
            gfxstate,
            heap,
            heap_offset,
            dds_info.width,
            dds_info.height,
            dds_info.format,
            dds_info.mip_map_count,
        ) catch unreachable;

        // Set a debug name
        {
            var path_u16: [300]u16 = undefined;
            assert(path.len < path_u16.len - 1);
            const path_len = std.unicode.utf8ToUtf16Le(path_u16[0..], path) catch unreachable;
            path_u16[path_len] = 0;
            _ = resource.SetName(@ptrCast(w32.LPCWSTR, &path_u16));
        }

        // Upload all subresources
        uploadSubResources(gfxstate, resource, subresources.items, d3d12.RESOURCE_STATES.GENERIC_READ);

        break :blk resource;
    };

    if (!in_frame) {
        // NOTE:(gmodarelli) If I schedule all of these uploads in a single frame I end up with all the textures
        // having the data from the first uploaded texture :(
        gfxstate.gctx.endFrame();
        gfxstate.gctx.finishGpuCommands();
    }

    // Create a persisten SRV descriptor for the texture
    const srv_allocation = gfxstate.gctx.allocatePersistentGpuDescriptors(1);
    gfxstate.gctx.device.CreateShaderResourceView(
        resource,
        null,
        srv_allocation.cpu_handle,
    );

    return gfx.Texture{
        .resource = resource,
        .persistent_descriptor = srv_allocation,
    };
}

fn allocateTextureMemory(gfxstate: *gfx.D3D12State, heap: *d3d12.IHeap, heap_offset: *u64, width: u32, height: u32, format: dxgi.FORMAT, mip_count: u32) !*d3d12.IResource {
    assert(gfxstate.gctx.is_cmdlist_opened);

    var heap_desc = heap.GetDesc();
    const heap_size = heap_desc.SizeInBytes;

    var resource: *d3d12.IResource = undefined;
    var desc = desc_blk: {
        var desc = d3d12.RESOURCE_DESC.initTex2d(
            format,
            width,
            height,
            mip_count,
        );
        desc.Flags = .{};
        break :desc_blk desc;
    };

    // TODO(gmodarelli): move this do d3d12.zig
    const d3d12_small_resource_placement_alignment: u32 = 4096;
    desc.Alignment = d3d12_small_resource_placement_alignment;
    var descs = [_]d3d12.RESOURCE_DESC{desc};
    var allocation_info = gfxstate.gctx.device.GetResourceAllocationInfo(0, 1, &descs);
    if (allocation_info.Alignment != d3d12_small_resource_placement_alignment) {
        desc.Alignment = 0;
        descs[0] = desc;
        allocation_info = gfxstate.gctx.device.GetResourceAllocationInfo(0, 1, &descs);
    }

    assert(heap_offset.* + allocation_info.SizeInBytes < heap_size);

    hrPanicOnFail(gfxstate.gctx.device.CreatePlacedResource(
        heap,
        heap_offset.*,
        &desc,
        .{ .COPY_DEST = true },
        null,
        &d3d12.IID_IResource,
        @ptrCast(*?*anyopaque, &resource),
    ));

    heap_offset.* += allocation_info.SizeInBytes;
    return resource;
}

fn uploadDataToTexture(gfxstate: *gfx.D3D12State, resource: *d3d12.IResource, data: *wic.IFormatConverter, state_after: d3d12.RESOURCE_STATES) !void {
    assert(gfxstate.gctx.is_cmdlist_opened);

    const desc = resource.GetDesc();

    var layout: [1]d3d12.PLACED_SUBRESOURCE_FOOTPRINT = undefined;
    var required_size: u64 = undefined;
    gfxstate.gctx.device.GetCopyableFootprints(&desc, 0, 1, 0, &layout, null, null, &required_size);

    const upload = gfxstate.gctx.allocateUploadBufferRegion(u8, @intCast(u32, required_size));
    layout[0].Offset = upload.buffer_offset;

    hrPanicOnFail(data.CopyPixels(
        null,
        layout[0].Footprint.RowPitch,
        layout[0].Footprint.RowPitch * layout[0].Footprint.Height,
        upload.cpu_slice.ptr,
    ));

    gfxstate.gctx.cmdlist.CopyTextureRegion(&d3d12.TEXTURE_COPY_LOCATION{
        .pResource = resource,
        .Type = .SUBRESOURCE_INDEX,
        .u = .{ .SubresourceIndex = 0 },
    }, 0, 0, 0, &d3d12.TEXTURE_COPY_LOCATION{
        .pResource = upload.buffer,
        .Type = .PLACED_FOOTPRINT,
        .u = .{ .PlacedFootprint = layout[0] },
    }, null);

    const barrier = d3d12.RESOURCE_BARRIER{
        .Type = .TRANSITION,
        .Flags = .{},
        .u = .{
            .Transition = .{
                .pResource = resource,
                .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
                .StateBefore = .{ .COPY_DEST = true },
                .StateAfter = state_after,
            },
        },
    };
    var barriers = [_]d3d12.RESOURCE_BARRIER{barrier};
    gfxstate.gctx.cmdlist.ResourceBarrier(1, &barriers);
}

fn uploadSubResources(gfxstate: *gfx.D3D12State, resource: *d3d12.IResource, subresources: []d3d12.SUBRESOURCE_DATA, state_after: d3d12.RESOURCE_STATES) void {
    assert(gfxstate.gctx.is_cmdlist_opened);

    const resource_desc = resource.GetDesc();

    for (0..subresources.len) |index| {
        const subresource_index = @intCast(u32, index);

        var layout: [1]d3d12.PLACED_SUBRESOURCE_FOOTPRINT = undefined;
        var num_rows: [1]u32 = undefined;
        var row_size_in_bytes: [1]u64 = undefined;
        var required_size: u64 = undefined;

        gfxstate.gctx.device.GetCopyableFootprints(
            &resource_desc,
            subresource_index,
            layout.len,
            0,
            &layout,
            &num_rows,
            &row_size_in_bytes,
            &required_size,
        );

        const upload = gfxstate.gctx.allocateUploadBufferRegion(u8, @intCast(u32, required_size));
        layout[0].Offset = upload.buffer_offset;

        var subresource = &subresources[subresource_index];
        var row: u32 = 0;
        const row_size_in_bytes_fixed = row_size_in_bytes[0];
        var cpu_slice_as_bytes = std.mem.sliceAsBytes(upload.cpu_slice);
        const subresource_slice = subresource.pData.?;
        while (row < num_rows[0]) : (row += 1) {
            const cpu_slice_begin = layout[0].Footprint.RowPitch * row;
            const cpu_slice_end = cpu_slice_begin + row_size_in_bytes_fixed;
            const subresource_slice_begin = row_size_in_bytes[0] * row;
            const subresource_slice_end = subresource_slice_begin + row_size_in_bytes_fixed;
            @memcpy(
                cpu_slice_as_bytes[cpu_slice_begin..cpu_slice_end],
                subresource_slice[subresource_slice_begin..subresource_slice_end],
            );
        }

        gfxstate.gctx.cmdlist.CopyTextureRegion(&.{
            .pResource = resource,
            .Type = .SUBRESOURCE_INDEX,
            .u = .{ .SubresourceIndex = subresource_index },
        }, 0, 0, 0, &.{
            .pResource = upload.buffer,
            .Type = .PLACED_FOOTPRINT,
            .u = .{ .PlacedFootprint = layout[0] },
        }, null);
    }

    const barrier = d3d12.RESOURCE_BARRIER{
        .Type = .TRANSITION,
        .Flags = .{},
        .u = .{
            .Transition = .{
                .pResource = resource,
                .Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
                .StateBefore = .{ .COPY_DEST = true },
                .StateAfter = state_after,
            },
        },
    };
    var barriers = [_]d3d12.RESOURCE_BARRIER{barrier};
    gfxstate.gctx.cmdlist.ResourceBarrier(1, &barriers);
}

fn loadTerrainLayer(
    name: []const u8,
    arena: std.mem.Allocator,
    gfxstate: *gfx.D3D12State,
    textures_heap: *d3d12.IHeap,
    textures_heap_offset: *u64,
) !TerrainLayer {
    const diffuse = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "content/textures/{s}_diff_2k.dds",
            .{name},
        ) catch unreachable;

        break :blk createDDSTextureFromFile(path, arena, gfxstate, textures_heap, textures_heap_offset, false) catch unreachable;
    };

    const normal = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "content/textures/{s}_nor_dx_2k.dds",
            .{name},
        ) catch unreachable;

        break :blk createDDSTextureFromFile(path, arena, gfxstate, textures_heap, textures_heap_offset, false) catch unreachable;
    };

    const arm = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "content/textures/{s}_arm_2k.dds",
            .{name},
        ) catch unreachable;

        break :blk createDDSTextureFromFile(path, arena, gfxstate, textures_heap, textures_heap_offset, false) catch unreachable;
    };

    return .{
        .diffuse = gfxstate.texture_pool.addTexture(diffuse),
        .normal = gfxstate.texture_pool.addTexture(normal),
        .arm = gfxstate.texture_pool.addTexture(arm),
    };
}

fn loadNodeHeightmap(
    gfxstate: *gfx.D3D12State,
    textures_heap: *d3d12.IHeap,
    textures_heap_offset: *u64,
    node: *QuadTreeNode,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    in_frame: bool,
    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    assert(node.heightmap_handle == null);

    const lookup = world_patch_manager.PatchLookup{
        .patch_x = @intCast(u16, node.patch_index[0]),
        .patch_z = @intCast(u16, node.patch_index[1]),
        .lod = @intCast(u4, node.mesh_lod),
        .patch_type_id = heightmap_patch_type_id,
    };

    const patch_info = world_patch_mgr.tryGetPatch(lookup, u8);
    if (patch_info.data_opt) |data| {
        const texture_desc = TextureDesc{
            .width = 65,
            .height = 65,
            .format = .R32_FLOAT,
            .data = data,
        };
        const heightmap = createTextureFromPixelBuffer(texture_desc, gfxstate, textures_heap, textures_heap_offset, in_frame) catch unreachable;
        node.heightmap_handle = gfxstate.texture_pool.addTexture(heightmap);
    }
}

fn loadNodeSplatmap(
    gfxstate: *gfx.D3D12State,
    textures_heap: *d3d12.IHeap,
    textures_heap_offset: *u64,
    node: *QuadTreeNode,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    in_frame: bool,
    splatmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    assert(node.splatmap_handle == null);

    const lookup = world_patch_manager.PatchLookup{
        .patch_x = @intCast(u16, node.patch_index[0]),
        .patch_z = @intCast(u16, node.patch_index[1]),
        .lod = @intCast(u4, node.mesh_lod),
        .patch_type_id = splatmap_patch_type_id,
    };

    const patch_info = world_patch_mgr.tryGetPatch(lookup, u8);
    if (patch_info.data_opt) |data| {
        const texture_desc = TextureDesc{
            .width = 65,
            .height = 65,
            .format = .R8_UNORM,
            .data = data,
        };
        const splatmap = createTextureFromPixelBuffer(texture_desc, gfxstate, textures_heap, textures_heap_offset, in_frame) catch unreachable;
        node.splatmap_handle = gfxstate.texture_pool.addTexture(splatmap);
    }
}

fn loadHeightAndSplatMaps(
    gfxstate: *gfx.D3D12State,
    textures_heap: *d3d12.IHeap,
    textures_heap_offset: *u64,
    node: *QuadTreeNode,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    in_frame: bool,
    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
    splatmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    if (node.heightmap_handle == null) {
        loadNodeHeightmap(gfxstate, textures_heap, textures_heap_offset, node, world_patch_mgr, in_frame, heightmap_patch_type_id) catch unreachable;
    }

    // NOTE(gmodarelli): avoid loading the splatmap if we haven't loaded the heightmap
    // This improves up startup times
    if (node.heightmap_handle == null) {
        return;
    }

    if (node.splatmap_handle == null) {
        loadNodeSplatmap(gfxstate, textures_heap, textures_heap_offset, node, world_patch_mgr, in_frame, splatmap_patch_type_id) catch unreachable;
    }
}

fn loadResources(
    allocator: std.mem.Allocator,
    quad_tree_nodes: *std.ArrayList(QuadTreeNode),
    gfxstate: *gfx.D3D12State,
    textures_heap: *d3d12.IHeap,
    textures_heap_offset: *u64,
    terrain_layers: *std.ArrayList(TerrainLayer),
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
    splatmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Load terrain layers textures
    {
        const dry_ground = loadTerrainLayer("dry_ground_rocks", arena, gfxstate, textures_heap, textures_heap_offset) catch unreachable;
        const forest_ground = loadTerrainLayer("forest_ground_01", arena, gfxstate, textures_heap, textures_heap_offset) catch unreachable;
        const rock_ground = loadTerrainLayer("rock_ground", arena, gfxstate, textures_heap, textures_heap_offset) catch unreachable;
        const snow = loadTerrainLayer("snow_02", arena, gfxstate, textures_heap, textures_heap_offset) catch unreachable;

        // NOTE: There's an implicit dependency on the order of the Splatmap here
        // - 0 dirt
        // - 1 grass
        // - 2 rock
        // - 3 snow
        terrain_layers.append(dry_ground) catch unreachable;
        terrain_layers.append(forest_ground) catch unreachable;
        terrain_layers.append(rock_ground) catch unreachable;
        terrain_layers.append(snow) catch unreachable;
    }

    // Ask the World Patch Manager to load all LOD3 for the current world extents
    const rid = world_patch_mgr.registerRequester(IdLocal.init("terrain_quad_tree"));
    const area = world_patch_manager.RequestRectangle{ .x = 0, .z = 0, .width = 4096, .height = 4096 };
    var lookups = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
    world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 3, &lookups);
    world_patch_manager.WorldPatchManager.getLookupsFromRectangle(splatmap_patch_type_id, area, 3, &lookups);
    world_patch_mgr.addLoadRequestFromLookups(rid, lookups.items, .high);
    // Make sure all LOD3 are resident
    world_patch_mgr.tickAll();

    // Request loading all the other LODs
    lookups.clearRetainingCapacity();
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 2, &lookups);
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(splatmap_patch_type_id, area, 2, &lookups);
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 1 &lookups);
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(splatmap_patch_type_id, area, 1, &lookups);
    // world_patch_mgr.addLoadRequestFromLookups(rid, lookups.items, .medium);

    // Load all LOD's heightmaps
    {
        var i: u32 = 0;
        while (i < quad_tree_nodes.items.len) : (i += 1) {
            var node = &quad_tree_nodes.items[i];
            loadHeightAndSplatMaps(
                gfxstate,
                textures_heap,
                textures_heap_offset,
                node,
                world_patch_mgr,
                false, // in frame
                heightmap_patch_type_id,
                splatmap_patch_type_id,
            ) catch unreachable;
        }
    }
}

fn divideQuadTreeNode(
    nodes: *std.ArrayList(QuadTreeNode),
    node: *QuadTreeNode,
) void {
    if (node.mesh_lod == 0) {
        return;
    }

    var child_index: u32 = 0;
    while (child_index < 4) : (child_index += 1) {
        var center_x = if (child_index % 2 == 0) node.center[0] - node.size[0] * 0.5 else node.center[0] + node.size[0] * 0.5;
        var center_y = if (child_index < 2) node.center[1] + node.size[1] * 0.5 else node.center[1] - node.size[1] * 0.5;
        var patch_index_x: u32 = if (child_index % 2 == 0) 0 else 1;
        var patch_index_y: u32 = if (child_index < 2) 1 else 0;

        var child_node = QuadTreeNode{
            .center = [2]f32{ center_x, center_y },
            .size = [2]f32{ node.size[0] * 0.5, node.size[1] * 0.5 },
            .child_indices = [4]u32{ invalid_index, invalid_index, invalid_index, invalid_index },
            .mesh_lod = node.mesh_lod - 1,
            .patch_index = [2]u32{ node.patch_index[0] * 2 + patch_index_x, node.patch_index[1] * 2 + patch_index_y },
            .heightmap_handle = null,
            .splatmap_handle = null,
        };

        node.child_indices[child_index] = @intCast(u32, nodes.items.len);
        nodes.appendAssumeCapacity(child_node);

        assert(node.child_indices[child_index] < nodes.items.len);
        divideQuadTreeNode(nodes, &nodes.items[node.child_indices[child_index]]);
    }
}

pub fn create(
    name: IdLocal,
    allocator: std.mem.Allocator,
    gfxstate: *gfx.D3D12State,
    flecs_world: *flecs.World,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
) !*SystemState {
    // Queries
    var query_builder_camera = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_camera
        .withReadonly(fd.Camera)
        .withReadonly(fd.Transform);
    var query_camera = query_builder_camera.buildQuery();

    var query_builder_lights = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_lights
        .with(fd.Light)
        .with(fd.Transform);
    var query_lights = query_builder_lights.buildQuery();

    // NOTE(gmodarelli): This should be part of gfx_d3d12.zig or texture.zig
    // but for now it's here to speed test it out and speed things along
    // NOTE(gmodarelli): We're currently loading up to 10880 1-channel R8_UNORM textures, so we need roughly
    // 150MB of space.
    const heap_desc = d3d12.HEAP_DESC{
        .SizeInBytes = 150 * 1024 * 1024,
        .Properties = d3d12.HEAP_PROPERTIES.initType(.DEFAULT),
        .Alignment = 0,
        .Flags = d3d12.HEAP_FLAGS.ALLOW_ONLY_NON_RT_DS_TEXTURES,
    };
    var textures_heap: *d3d12.IHeap = undefined;
    hrPanicOnFail(gfxstate.gctx.device.CreateHeap(&heap_desc, &d3d12.IID_IHeap, @ptrCast(*?*anyopaque, &textures_heap)));
    var textures_heap_offset: u64 = 0;

    // TODO(gmodarelli): This is just enough for a single sector, but it's good for testing
    const max_quad_tree_nodes: usize = 85 * 64;
    var terrain_quad_tree_nodes = std.ArrayList(QuadTreeNode).initCapacity(allocator, max_quad_tree_nodes) catch unreachable;
    var quads_to_render = std.ArrayList(u32).init(allocator);
    var quads_to_load = std.ArrayList(u32).init(allocator);

    // Create initial sectors
    {
        var patch_half_size = @intToFloat(f32, config.largest_patch_width) / 2.0;
        var patch_y: u32 = 0;
        while (patch_y < 8) : (patch_y += 1) {
            var patch_x: u32 = 0;
            while (patch_x < 8) : (patch_x += 1) {
                terrain_quad_tree_nodes.appendAssumeCapacity(.{
                    .center = [2]f32{
                        @intToFloat(f32, patch_x * config.largest_patch_width) + patch_half_size,
                        @intToFloat(f32, patch_y * config.largest_patch_width) + patch_half_size,
                    },
                    .size = [2]f32{ patch_half_size, patch_half_size },
                    .child_indices = [4]u32{ invalid_index, invalid_index, invalid_index, invalid_index },
                    .mesh_lod = 3,
                    .patch_index = [2]u32{ patch_x, patch_y },
                    .heightmap_handle = null,
                    .splatmap_handle = null,
                });
            }
        }

        assert(terrain_quad_tree_nodes.items.len == 64);

        var sector_index: u32 = 0;
        while (sector_index < 64) : (sector_index += 1) {
            var node = &terrain_quad_tree_nodes.items[sector_index];
            divideQuadTreeNode(&terrain_quad_tree_nodes, node);
        }
    }

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var meshes = std.ArrayList(Mesh).init(allocator);
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_vertices = std.ArrayList(Vertex).init(arena);

    loadMesh(allocator, "content/meshes/LOD0.obj", &meshes, &meshes_indices, &meshes_vertices) catch unreachable;
    loadMesh(allocator, "content/meshes/LOD1.obj", &meshes, &meshes_indices, &meshes_vertices) catch unreachable;
    loadMesh(allocator, "content/meshes/LOD2.obj", &meshes, &meshes_indices, &meshes_vertices) catch unreachable;
    loadMesh(allocator, "content/meshes/LOD3.obj", &meshes, &meshes_indices, &meshes_vertices) catch unreachable;

    const total_num_vertices = @intCast(u32, meshes_vertices.items.len);
    const total_num_indices = @intCast(u32, meshes_indices.items.len);

    // Create a vertex buffer.
    var vertex_buffer = gfxstate.createBuffer(.{
        .size = total_num_vertices * @sizeOf(Vertex),
        .state = d3d12.RESOURCE_STATES.GENERIC_READ,
        .name = L("Terrain Quad Tree Vertex Buffer"),
        .persistent = true,
        .has_cbv = false,
        .has_srv = true,
        .has_uav = false,
    }) catch unreachable;

    // Create an index buffer.
    var index_buffer = gfxstate.createBuffer(.{
        .size = total_num_indices * @sizeOf(IndexType),
        .state = .{ .INDEX_BUFFER = true },
        .name = L("Terrain Quad Tree Index Buffer"),
        .persistent = false,
        .has_cbv = false,
        .has_srv = false,
        .has_uav = false,
    }) catch unreachable;

    const heightmap_patch_type_id = world_patch_mgr.getPatchTypeId(IdLocal.init("heightmap"));
    const splatmap_patch_type_id = world_patch_mgr.getPatchTypeId(IdLocal.init("splatmap"));

    var terrain_layers = std.ArrayList(TerrainLayer).init(arena);
    loadResources(
        allocator,
        &terrain_quad_tree_nodes,
        gfxstate,
        textures_heap,
        &textures_heap_offset,
        &terrain_layers,
        world_patch_mgr,
        heightmap_patch_type_id,
        splatmap_patch_type_id,
    ) catch unreachable;

    var terrain_layers_buffer = gfxstate.createBuffer(.{
        .size = terrain_layers.items.len * @sizeOf(TerrainLayerTextureIndices),
        .state = d3d12.RESOURCE_STATES.GENERIC_READ,
        .name = L("Terrain Layers Buffer"),
        .persistent = true,
        .has_cbv = false,
        .has_srv = true,
        .has_uav = false,
    }) catch unreachable;

    // Create instance buffers.
    const instance_data_buffers = blk: {
        var buffers: [gfx.D3D12State.num_buffered_frames]gfx.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const bufferDesc = gfx.BufferDesc{
                .size = max_instances * @sizeOf(InstanceData),
                .state = d3d12.RESOURCE_STATES.GENERIC_READ,
                .name = L("Terrain Quad Tree Instance Data Buffer"),
                .persistent = true,
                .has_cbv = false,
                .has_srv = true,
                .has_uav = false,
            };

            buffers[buffer_index] = gfxstate.createBuffer(bufferDesc) catch unreachable;
        }

        break :blk buffers;
    };

    var draw_calls = std.ArrayList(DrawCall).init(allocator);
    var instance_data = std.ArrayList(InstanceData).init(allocator);

    gfxstate.scheduleUploadDataToBuffer(Vertex, vertex_buffer, 0, meshes_vertices.items);
    gfxstate.scheduleUploadDataToBuffer(IndexType, index_buffer, 0, meshes_indices.items);

    var terrain_layer_texture_indices = std.ArrayList(TerrainLayerTextureIndices).initCapacity(arena, terrain_layers.items.len) catch unreachable;
    var terrain_layer_index: u32 = 0;
    while (terrain_layer_index < terrain_layers.items.len) : (terrain_layer_index += 1) {
        const terrain_layer = &terrain_layers.items[terrain_layer_index];
        const diffuse = gfxstate.lookupTexture(terrain_layer.diffuse);
        const normal = gfxstate.lookupTexture(terrain_layer.normal);
        const arm = gfxstate.lookupTexture(terrain_layer.arm);
        terrain_layer_texture_indices.appendAssumeCapacity(.{
            .diffuse_index = diffuse.?.persistent_descriptor.index,
            .normal_index = normal.?.persistent_descriptor.index,
            .arm_index = arm.?.persistent_descriptor.index,
            .padding = 42,
        });
    }
    gfxstate.scheduleUploadDataToBuffer(TerrainLayerTextureIndices, terrain_layers_buffer, 0, terrain_layer_texture_indices.items);

    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });

    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .world_patch_mgr = world_patch_mgr,
        .sys = sys,
        .gfx = gfxstate,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .instance_data_buffers = instance_data_buffers,
        .draw_calls = draw_calls,
        .textures_heap = textures_heap,
        .textures_heap_offset = textures_heap_offset,
        .instance_data = instance_data,
        .terrain_layers_buffer = terrain_layers_buffer,
        .terrain_lod_meshes = meshes,
        .terrain_quad_tree_nodes = terrain_quad_tree_nodes,
        .quads_to_render = quads_to_render,
        .quads_to_load = quads_to_load,
        .query_camera = query_camera,
        .query_lights = query_lights,
        .heightmap_patch_type_id = heightmap_patch_type_id,
        .splatmap_patch_type_id = splatmap_patch_type_id,
    };

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_camera.deinit();
    state.query_lights.deinit();

    state.gfx.releaseAllTextures();
    _ = state.textures_heap.Release();
    state.textures_heap.* = undefined;

    state.terrain_lod_meshes.deinit();
    state.instance_data.deinit();
    state.terrain_quad_tree_nodes.deinit();
    state.quads_to_render.deinit();
    state.quads_to_load.deinit();
    state.draw_calls.deinit();
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

    var arena_state = std.heap.ArenaAllocator.init(state.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const CameraQueryComps = struct {
        cam: *const fd.Camera,
        transform: *const fd.Transform,
    };
    var camera_comps: ?CameraQueryComps = blk: {
        var entity_iter_camera = state.query_camera.iterator(CameraQueryComps);
        while (entity_iter_camera.next()) |comps| {
            if (comps.cam.active) {
                break :blk comps;
            }
        }

        break :blk null;
    };

    if (camera_comps == null) {
        return;
    }

    const cam = camera_comps.?.cam;
    const camera_position = camera_comps.?.transform.getPos00();
    const cam_world_to_clip = zm.loadMat(cam.world_to_clip[0..]);
    state.gpu_frame_profiler_index = state.gfx.gpu_profiler.startProfile(state.gfx.gctx.cmdlist, "Terrain Quad Tree");

    const pipeline_info = state.gfx.getPipeline(IdLocal.init("terrain_quad_tree"));
    state.gfx.gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

    state.gfx.gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
    const index_buffer = state.gfx.lookupBuffer(state.index_buffer);
    const index_buffer_resource = state.gfx.gctx.lookupResource(index_buffer.?.resource);
    state.gfx.gctx.cmdlist.IASetIndexBuffer(&.{
        .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
        .SizeInBytes = @intCast(c_uint, index_buffer_resource.?.GetDesc().Width),
        .Format = if (@sizeOf(IndexType) == 2) .R16_UINT else .R32_UINT,
    });

    // Upload per-scene constant data.
    {
        const ibl_textures = state.gfx.lookupIBLTextures();
        const mem = state.gfx.gctx.allocateUploadMemory(SceneUniforms, 1);
        mem.cpu_slice[0].radiance_texture_index = ibl_textures.radiance.?.persistent_descriptor.index;
        mem.cpu_slice[0].irradiance_texture_index = ibl_textures.irradiance.?.persistent_descriptor.index;
        mem.cpu_slice[0].brdf_integration_texture_index = ibl_textures.brdf.?.persistent_descriptor.index;
        state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(2, mem.gpu_base);
    }

    // Upload per-frame constant data.
    {
        const environment_info = state.flecs_world.getSingletonMut(fd.EnvironmentInfo).?;
        const world_time = environment_info.world_time;
        const mem = state.gfx.gctx.allocateUploadMemory(FrameUniforms, 1);
        mem.cpu_slice[0].world_to_clip = zm.transpose(cam_world_to_clip);
        mem.cpu_slice[0].camera_position = camera_position;
        mem.cpu_slice[0].time = world_time;
        mem.cpu_slice[0].noise_offset_y = config.noise_offset_y;
        mem.cpu_slice[0].noise_scale_y = config.noise_scale_y;
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

            light_i += 1;
        }
        mem.cpu_slice[0].light_count = light_i;

        state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
    }

    // Reset transforms, materials and draw calls array list
    state.quads_to_render.clearRetainingCapacity();
    state.quads_to_load.clearRetainingCapacity();
    state.instance_data.clearRetainingCapacity();
    state.draw_calls.clearRetainingCapacity();

    {
        var sector_index: u32 = 0;
        while (sector_index < 64) : (sector_index += 1) {
            const lod3_node = &state.terrain_quad_tree_nodes.items[sector_index];
            const camera_point = [2]f32{ camera_position[0], camera_position[2] };

            collectQuadsToRenderForSector(
                state,
                camera_point,
                lod_load_range,
                lod3_node,
                sector_index,
                arena,
            ) catch unreachable;
        }
    }

    {
        // TODO: Batch quads together by mesh lod
        var start_instance_location: u32 = 0;
        for (state.quads_to_render.items) |quad_index| {
            const quad = &state.terrain_quad_tree_nodes.items[quad_index];

            const object_to_world = zm.translation(quad.center[0], 0.0, quad.center[1]);
            // TODO: Generate from quad.patch_index
            const heightmap = state.gfx.lookupTexture(quad.heightmap_handle.?);
            const splatmap = state.gfx.lookupTexture(quad.splatmap_handle.?);
            state.instance_data.append(.{
                .object_to_world = zm.transpose(object_to_world),
                .heightmap_index = heightmap.?.persistent_descriptor.index,
                .splatmap_index = splatmap.?.persistent_descriptor.index,
                .padding1 = 42,
                .padding2 = 42,
            }) catch unreachable;

            const mesh = state.terrain_lod_meshes.items[quad.mesh_lod];

            state.draw_calls.append(.{
                .mesh_index = 0,
                .index_count = mesh.lods[0].index_count,
                .instance_count = 1,
                .index_offset = mesh.lods[0].index_offset,
                .vertex_offset = @intCast(i32, mesh.lods[0].vertex_offset),
                .start_instance_location = start_instance_location,
            }) catch unreachable;

            start_instance_location += 1;
        }
    }

    const frame_index = state.gfx.gctx.frame_index;
    if (state.instance_data.items.len > 0) {
        state.gfx.uploadDataToBuffer(InstanceData, state.instance_data_buffers[frame_index], 0, state.instance_data.items);
    }

    const vertex_buffer = state.gfx.lookupBuffer(state.vertex_buffer);
    const instance_data_buffer = state.gfx.lookupBuffer(state.instance_data_buffers[frame_index]);
    const terrain_layers_buffer = state.gfx.lookupBuffer(state.terrain_layers_buffer);

    for (state.draw_calls.items) |draw_call| {
        const mem = state.gfx.gctx.allocateUploadMemory(DrawUniforms, 1);
        mem.cpu_slice[0].start_instance_location = draw_call.start_instance_location;
        mem.cpu_slice[0].vertex_offset = draw_call.vertex_offset;
        mem.cpu_slice[0].vertex_buffer_index = vertex_buffer.?.persistent_descriptor.index;
        mem.cpu_slice[0].instance_data_buffer_index = instance_data_buffer.?.persistent_descriptor.index;
        mem.cpu_slice[0].terrain_layers_buffer_index = terrain_layers_buffer.?.persistent_descriptor.index;
        state.gfx.gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

        state.gfx.gctx.cmdlist.DrawIndexedInstanced(
            draw_call.index_count,
            draw_call.instance_count,
            draw_call.index_offset,
            draw_call.vertex_offset,
            draw_call.start_instance_location,
        );
    }

    state.gfx.gpu_profiler.endProfile(state.gfx.gctx.cmdlist, state.gpu_frame_profiler_index, state.gfx.gctx.frame_index);

    for (state.quads_to_load.items) |quad_index| {
        var node = &state.terrain_quad_tree_nodes.items[quad_index];
        loadHeightAndSplatMaps(
            state.gfx,
            state.textures_heap,
            &state.textures_heap_offset,
            node,
            state.world_patch_mgr,
            true, // in frame
            state.heightmap_patch_type_id,
            state.splatmap_patch_type_id,
        ) catch unreachable;
    }

    // Load high-lod patches near camera
    if (tides_math.dist3_xz(state.cam_pos_old, camera_position) > 32) {
        var lookups_old = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        var lookups_new = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        for (0..3) |lod| {
            lookups_old.clearRetainingCapacity();
            lookups_new.clearRetainingCapacity();

            const area_width = 1 * config.patch_size * @intToFloat(f32, std.math.pow(usize, 2, lod));

            const area_old = world_patch_manager.RequestRectangle{
                .x = state.cam_pos_old[0] - area_width,
                .z = state.cam_pos_old[2] - area_width,
                .width = area_width * 2,
                .height = area_width * 2,
            };

            const area_new = world_patch_manager.RequestRectangle{
                .x = camera_position[0] - area_width,
                .z = camera_position[2] - area_width,
                .width = area_width * 2,
                .height = area_width * 2,
            };

            const lod_u4 = @intCast(u4, lod);
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(state.heightmap_patch_type_id, area_old, lod_u4, &lookups_old);
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(state.splatmap_patch_type_id, area_old, lod_u4, &lookups_old);
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(state.heightmap_patch_type_id, area_new, lod_u4, &lookups_new);
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(state.splatmap_patch_type_id, area_new, lod_u4, &lookups_new);

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

            const rid = state.world_patch_mgr.getRequester(IdLocal.init("terrain_quad_tree")); // HACK(Anders)
            // NOTE(Anders): HACK
            if (state.cam_pos_old[0] != -100000) {
                state.world_patch_mgr.removeLoadRequestFromLookups(rid, lookups_old.items);
            }

            state.world_patch_mgr.addLoadRequestFromLookups(rid, lookups_new.items, .medium);
        }

        state.cam_pos_old = camera_position;
    }
}

// Algorithm that walks a quad tree and generates a list of quad tree nodes to render
fn collectQuadsToRenderForSector(state: *SystemState, position: [2]f32, range: f32, node: *QuadTreeNode, node_index: u32, allocator: std.mem.Allocator) !void {
    assert(node_index != invalid_index);

    if (node.mesh_lod == 0) {
        return;
    }

    if (node.containedInsideChildren(position, range, &state.terrain_quad_tree_nodes) and node.areChildrenLoaded(&state.terrain_quad_tree_nodes)) {
        var higher_lod_node_indices: [4]u32 = .{ invalid_index, invalid_index, invalid_index, invalid_index };
        for (node.child_indices, 0..) |node_child_index, i| {
            var child_node = &state.terrain_quad_tree_nodes.items[node_child_index];
            if (child_node.nearPoint(position, range)) {
                if (child_node.mesh_lod == 1 and child_node.areChildrenLoaded(&state.terrain_quad_tree_nodes)) {
                    state.quads_to_render.appendSlice(child_node.child_indices[0..4]) catch unreachable;
                } else if (child_node.mesh_lod == 1 and !child_node.areChildrenLoaded(&state.terrain_quad_tree_nodes)) {
                    state.quads_to_render.append(node_child_index) catch unreachable;
                    state.quads_to_load.appendSlice(child_node.child_indices[0..4]) catch unreachable;
                } else if (child_node.mesh_lod > 1) {
                    higher_lod_node_indices[i] = node_child_index;
                }
            } else {
                state.quads_to_render.append(node_child_index) catch unreachable;
            }
        }

        for (higher_lod_node_indices) |higher_lod_node_index| {
            if (higher_lod_node_index != invalid_index) {
                var child_node = &state.terrain_quad_tree_nodes.items[higher_lod_node_index];
                collectQuadsToRenderForSector(state, position, range, child_node, higher_lod_node_index, allocator) catch unreachable;
            } else {
                // state.quads_to_render.append(node.child_indices[i]) catch unreachable;
            }
        }
    } else if (node.containedInsideChildren(position, range, &state.terrain_quad_tree_nodes) and !node.areChildrenLoaded(&state.terrain_quad_tree_nodes)) {
        state.quads_to_render.append(node_index) catch unreachable;
        state.quads_to_load.appendSlice(node.child_indices[0..4]) catch unreachable;
    } else {
        if (node.isLoaded()) {
            state.quads_to_render.append(node_index) catch unreachable;
        } else {
            state.quads_to_load.append(node_index) catch unreachable;
        }
    }
}
