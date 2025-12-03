const std = @import("std");
const IdLocal = @import("../core/core.zig").IdLocal;
const zm = @import("zmath");
const fd = @import("../config/flecs_data.zig");
const renderer = @import("renderer.zig");
const geometry = @import("geometry.zig");

pub const InvalidResourceIndex = std.math.maxInt(u32);

pub const DebugFrame = struct {
    view: [16]f32,
    proj: [16]f32,
    view_proj: [16]f32,
    view_proj_inv: [16]f32,

    debug_line_point_count_max: u32,
    debug_line_point_args_buffer_index: u32,
    debug_line_vertex_buffer_index: u32,
    _padding1: u32,
};

pub const GpuLight = struct {
    position: [3]f32, // Direction for directional light
    light_type: u32, // 0 - Directional, 1 - Point
    color: [3]f32,
    intensity: f32,
    radius: f32 = 0, // Unused for directional light
    shadow_intensity: f32 = 0,
    _padding: [2]f32 = [2]f32{ 42, 42 },
};

pub const PointLight = extern struct {
    position: [3]f32,
    radius: f32,
    color: [3]f32,
    intensity: f32,
};

pub const DirectionalLight = extern struct {
    direction: [3]f32,
    color: [3]f32,
    intensity: f32,
    world_inv: [16]f32,
    cast_shadows: bool,
    shadow_intensity: f32,
};

pub const HeightFogSettings = struct {
    color: [3]f32 = [3]f32{ 0, 0, 0 },
    density: f32 = 0,
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32,
    height: f32,
    pub fn setPos(self: *Rect, x: f32, y: f32) void {
        self.x = x;
        self.y = y;
    }
    pub fn setSize(self: *Rect, width: f32, height: f32) void {
        self.width = width;
        self.height = height;
    }
};

pub const UiImage = struct {
    rect: [4]f32, // top, right, bottom, left
    color: [4]f32,
    texture_index: u32,
    render_order: i32,
    _padding0: [2]u32,
};

pub const UpdateDesc = struct {
    time_of_day_01: f32 = 0.0,
    sun_light: DirectionalLight = undefined,
    moon_light: DirectionalLight = undefined,
    point_lights: *std.ArrayList(PointLight) = undefined,
    height_fog: HeightFogSettings = undefined,

    // Entities
    ocean_tiles: *std.ArrayList(OceanTile) = undefined,
    // static_entities: *std.ArrayList(RenderableEntity) = undefined,
    added_static_entities: std.ArrayList(RenderableEntity) = undefined,
    removed_static_entities: std.ArrayList(RenderableEntityId) = undefined,
    dynamic_entities: *std.ArrayList(DynamicEntity) = undefined,
    ui_images: *std.ArrayList(UiImage) = undefined,
};

pub const InstanceData = struct {
    object_to_world: [16]f32,
    world_to_object: [16]f32,
    material_index: u32,
    _padding: [3]f32,
};

pub const InstanceDataIndirection = struct {
    instance_index: u32,
    gpu_mesh_index: u32,
    material_index: u32,
    entity_id: u32,
};

pub const InstanceRootConstants = struct {
    start_instance_location: u32,
    instance_data_buffer_index: u32,
    instance_material_buffer_index: u32,
};

pub const TerrainInstanceData = struct {
    object_to_world: [16]f32,
    heightmap_index: u32,
    lod: u32,
    padding1: [2]u32,
};

pub const OceanTile = struct {
    world: zm.Mat = undefined,
    scale: f32 = 0,
};

pub const RenderableEntityId = u64;
pub const RenderableEntity = struct {
    entity_id: RenderableEntityId,
    renderable_id: IdLocal,
    world: zm.Mat,
    // Debug
    draw_bounds: bool = false,
};

pub const DynamicEntity = struct {
    world: zm.Mat = undefined,
    position: [3]f32 = undefined,
    scale: f32 = 0,
    lod_count: u32 = 0,
    lods: [geometry.mesh_lod_max_count]Lod = undefined,
};

pub const Lod = struct {
    mesh_handle: renderer.LegacyMeshHandle,
    materials: [geometry.sub_mesh_max_count]IdLocal,
    materials_count: u32,
};

pub const Frustum = struct {
    planes: [4][4]f32 = undefined,

    pub fn init(self: *@This(), view_projection: zm.Mat) void {
        // Left plane
        self.planes[0][0] = view_projection[0][3] + view_projection[0][0];
        self.planes[0][1] = view_projection[1][3] + view_projection[1][0];
        self.planes[0][2] = view_projection[2][3] + view_projection[2][0];
        self.planes[0][3] = view_projection[3][3] + view_projection[3][0];

        // Right plane
        self.planes[1][0] = view_projection[0][3] - view_projection[0][0];
        self.planes[1][1] = view_projection[1][3] - view_projection[1][0];
        self.planes[1][2] = view_projection[2][3] - view_projection[2][0];
        self.planes[1][3] = view_projection[3][3] - view_projection[3][0];

        // Top plane
        self.planes[2][0] = view_projection[0][3] - view_projection[0][1];
        self.planes[2][1] = view_projection[1][3] - view_projection[1][1];
        self.planes[2][2] = view_projection[2][3] - view_projection[2][1];
        self.planes[2][3] = view_projection[3][3] - view_projection[3][1];

        // Bottom plane
        self.planes[3][0] = view_projection[0][3] + view_projection[0][1];
        self.planes[3][1] = view_projection[1][3] + view_projection[1][1];
        self.planes[3][2] = view_projection[2][3] + view_projection[2][1];
        self.planes[3][3] = view_projection[3][3] + view_projection[3][1];

        // TODO(gmodarelli): Figure out what these become when Z is reversed
        // // Near plane
        // self.planes[4][0] = view_projection[0][2];
        // self.planes[4][1] = view_projection[1][2];
        // self.planes[4][2] = view_projection[2][2];
        // self.planes[4][3] = view_projection[3][2];

        // // Far plane
        // self.planes[5][0] = view_projection[0][3] - view_projection[0][2];
        // self.planes[5][1] = view_projection[1][3] - view_projection[1][2];
        // self.planes[5][2] = view_projection[2][3] - view_projection[2][2];
        // self.planes[5][3] = view_projection[3][3] - view_projection[3][2];

        for (&self.planes) |*plane| {
            const length = std.math.sqrt(plane[0] * plane[0] + plane[1] * plane[1] + plane[2] * plane[2]);
            plane[0] = plane[0] / length;
            plane[1] = plane[1] / length;
            plane[2] = plane[2] / length;
            plane[3] = plane[3] / length;
        }
    }

    pub fn isVisible(self: *const @This(), center: [3]f32, radius: f32) bool {
        for (self.planes) |plane| {
            if (distanceToPoint(plane, center) + radius < 0.0) {
                return false;
            }
        }

        return true;
    }

    fn distanceToPoint(plane: [4]f32, point: [3]f32) f32 {
        return plane[0] * point[0] + plane[1] * point[1] + plane[2] * point[2] + plane[3] * plane[3];
    }
};
