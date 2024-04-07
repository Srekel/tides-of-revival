const std = @import("std");
const zphy = @import("zphysics");
const zm = @import("zmath");
const ecs = @import("zflecs");
const window = @import("../renderer/window.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const renderer = @import("../renderer/renderer.zig");
const MeshHandle = renderer.MeshHandle;
const TextureHandle = renderer.TextureHandle;

pub fn registerComponents(ecsu_world: ecsu.World) void {
    const ecs_world = ecsu_world.world;
    ecs.TAG(ecs_world, NOCOMP);
    ecs.TAG(ecs_world, LocalSpace);
    ecs.TAG(ecs_world, WorldSpace);
    ecs.COMPONENT(ecs_world, ColorRGB);
    ecs.COMPONENT(ecs_world, ColorRGBRoughness);
    ecs.COMPONENT(ecs_world, Position);
    ecs.COMPONENT(ecs_world, Forward);
    ecs.COMPONENT(ecs_world, Rotation);
    ecs.COMPONENT(ecs_world, EulerRotation);
    ecs.COMPONENT(ecs_world, Scale);
    ecs.COMPONENT(ecs_world, Transform);
    ecs.COMPONENT(ecs_world, Dynamic);
    ecs.COMPONENT(ecs_world, Velocity);
    ecs.COMPONENT(ecs_world, StaticMeshComponent);
    ecs.COMPONENT(ecs_world, SkyLightComponent);
    ecs.COMPONENT(ecs_world, UIImageComponent);
    ecs.COMPONENT(ecs_world, CICamera);
    ecs.COMPONENT(ecs_world, Camera);
    // ecs.COMPONENT(ecs_world, CIPhysicsBody);
    ecs.COMPONENT(ecs_world, PhysicsBody);
    ecs.COMPONENT(ecs_world, TerrainPatchLookup);
    ecs.COMPONENT(ecs_world, WorldLoader);
    ecs.COMPONENT(ecs_world, WorldPatch);
    // ecs.COMPONENT(ecs_world, ComponentData);
    ecs.COMPONENT(ecs_world, DirectionalLightComponent);
    ecs.COMPONENT(ecs_world, PointLightComponent);
    ecs.COMPONENT(ecs_world, CIFSM);
    ecs.COMPONENT(ecs_world, FSM);
    ecs.COMPONENT(ecs_world, Input);
    ecs.COMPONENT(ecs_world, Interactor);
    ecs.COMPONENT(ecs_world, SpawnPoint);
    ecs.COMPONENT(ecs_world, Health);
    ecs.COMPONENT(ecs_world, Speed);
    ecs.COMPONENT(ecs_world, Quality);
    ecs.COMPONENT(ecs_world, Effect);
    ecs.COMPONENT(ecs_world, CompCity);
    ecs.COMPONENT(ecs_world, CompBanditCamp);
    ecs.COMPONENT(ecs_world, CompCaravan);
    ecs.COMPONENT(ecs_world, CompCombatant);
    ecs.COMPONENT(ecs_world, EnvironmentInfo);
    ecs.COMPONENT(ecs_world, ProjectileWeapon);
    ecs.COMPONENT(ecs_world, Projectile);
}

// pub const GameContext = struct {
//     constvars: std.AutoHashMap(IdLocal, []const u8),
//     vars: std.AutoHashMap(IdLocal, []u8),
//     fn getConst(self: GameContext, comptime T: type, id: IdLocal) *const T {

//     }
// };

pub const NOCOMP = struct {
    // dummy: u32 = 0,
};

pub const ColorRGB = struct {
    r: f32,
    g: f32,
    b: f32,
    pub fn init(r: f32, g: f32, b: f32) ColorRGB {
        return .{ .r = r, .g = g, .b = b };
    }
    pub fn elems(self: *ColorRGB) *[3]f32 {
        return @as(*[3]f32, @ptrCast(&self.r));
    }
    pub fn elemsConst(self: *const ColorRGB) *const [3]f32 {
        return @as(*const [3]f32, @ptrCast(&self.r));
    }
};
pub const ColorRGBRoughness = struct { r: f32, g: f32, b: f32, roughness: f32 };

pub const LocalSpace = struct {};
pub const WorldSpace = struct {};

pub const Position = struct {
    x: f32,
    y: f32,
    z: f32,
    pub fn init(x: f32, y: f32, z: f32) Position {
        return .{ .x = x, .y = y, .z = z };
    }
    pub fn elems(self: *Position) *[3]f32 {
        return @as(*[3]f32, @ptrCast(&self.x));
    }
    pub fn elemsConst(self: *const Position) *const [3]f32 {
        return @as(*const [3]f32, @ptrCast(&self.x));
    }
    pub fn asZM(self: *const Position) zm.F32x4 {
        return zm.loadArr3(self.elemsConst().*);
    }
    pub fn fromZM(self: *Position, pos_z: zm.F32x4) void {
        zm.storeArr3(self.elems(), pos_z);
    }
};

pub const Forward = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 1,
    pub fn elems(self: *Forward) *[3]f32 {
        return @as(*[3]f32, @ptrCast(&self.x));
    }
    pub fn elemsConst(self: *const Forward) *const [3]f32 {
        return @as(*const [3]f32, @ptrCast(&self.x));
    }
    pub fn asZM(self: *const Forward) zm.F32x4 {
        return zm.loadArr3(self.elemsConst().*);
    }
};

pub const Rotation = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 1,
    pub fn initFromEuler(pitch: f32, yaw: f32, roll: f32) Rotation {
        const rot_z = zm.quatFromRollPitchYaw(pitch, yaw, roll);
        var rot = Rotation{};
        zm.storeArr4(rot.elems(), rot_z);
        return rot;
    }
    pub fn initFromEulerDegrees(pitch: f32, yaw: f32, roll: f32) Rotation {
        return initFromEuler(std.math.degreesToRadians(f32, pitch), std.math.degreesToRadians(f32, yaw), std.math.degreesToRadians(f32, roll));
    }
    pub fn elems(self: *Rotation) *[4]f32 {
        return @as(*[4]f32, @ptrCast(&self.x));
    }
    pub fn elemsConst(self: *const Rotation) *const [4]f32 {
        return @as(*const [4]f32, @ptrCast(&self.x));
    }
    pub fn asZM(self: *const Rotation) zm.Quat {
        return zm.loadArr4(self.elemsConst().*);
    }
    pub fn fromZM(self: *Rotation, rot_z: zm.Quat) void {
        zm.storeArr4(self.elems(), rot_z);
    }
};

pub const EulerRotation = struct {
    roll: f32 = 0,
    pitch: f32 = 0,
    yaw: f32 = 0,
    pub fn init(pitch: f32, yaw: f32, roll: f32) EulerRotation {
        return .{ .pitch = pitch, .yaw = yaw, .roll = roll };
    }
    pub fn elems(self: *EulerRotation) *[3]f32 {
        return @as(*[3]f32, @ptrCast(&self.roll));
    }
    pub fn elemsConst(self: *const EulerRotation) *const [3]f32 {
        return @as(*const [3]f32, @ptrCast(&self.roll));
    }
};

pub const Scale = struct {
    x: f32 = 1,
    y: f32 = 1,
    z: f32 = 1,

    pub fn create(x: f32, y: f32, z: f32) Scale {
        return .{ .x = x, .y = y, .z = z };
    }
    pub fn createScalar(scale: f32) Scale {
        return .{ .x = scale, .y = scale, .z = scale };
    }
    pub fn elems(self: *Scale) *[3]f32 {
        return @as(*[3]f32, @ptrCast(&self.x));
    }
    pub fn elemsConst(self: *const Scale) *const [3]f32 {
        return @as(*const [3]f32, @ptrCast(&self.x));
    }
};

pub const Transform = struct {
    matrix: [12]f32 = undefined,

    pub fn init(x: f32, y: f32, z: f32) Transform {
        return .{
            .matrix = [_]f32{
                1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, 1.0,
                x,   y,   z,
            },
        };
    }
    pub fn initFromPosition(pos: Position) Transform {
        return .{
            .matrix = [_]f32{
                1.0,   0.0,   0.0,
                0.0,   1.0,   0.0,
                0.0,   0.0,   1.0,
                pos.x, pos.y, pos.z,
            },
        };
    }
    pub fn initWithScale(x: f32, y: f32, z: f32, scale: f32) Transform {
        return .{
            .matrix = [_]f32{
                scale, 0.0,   0.0,
                0.0,   scale, 0.0,
                0.0,   0.0,   scale,
                x,     y,     z,
            },
        };
    }

    pub fn initWithQuaternion(quat: [4]f32) Transform {
        const z_rotation_matrix = zm.matFromQuat(zm.Quat{ quat[0], quat[1], quat[2], quat[3] });
        var transform = Transform{};
        zm.storeMat43(&transform.matrix, z_rotation_matrix);
        return transform;
    }

    pub fn getPos00(self: Transform) [3]f32 {
        return self.matrix[9..].*;
    }

    pub fn getPos(self: *Transform) []f32 {
        return self.matrix[9..];
    }

    pub fn setPos(self: *Transform, pos: [3]f32) void {
        self.matrix[9..].* = pos;
    }

    pub fn getRotPitchRollYaw(self: Transform) [3]f32 {
        const mat = zm.loadMat43(&self.matrix);
        const quat = zm.matToQuat(mat);
        const zyx = zm.quatToRollPitchYaw(quat);
        return .{ zyx[0], zyx[1], zyx[2] };
    }

    pub fn getRotQuaternion(self: Transform) [4]f32 {
        const mat = zm.loadMat43(&self.matrix);
        const quat = zm.matToQuat(mat);
        var out: [4]f32 = undefined;
        zm.storeArr4(&out, quat);
        return out;
    }

    pub fn setScale(self: *Transform, scale: [3]f32) void {
        self.matrix[0] = scale[0];
        self.matrix[4] = scale[1];
        self.matrix[8] = scale[2];
    }

    pub fn asZM(self: *const Transform) zm.Mat {
        return zm.loadMat43(&self.matrix);
    }

    pub fn fromZM(self: *Transform, mat_z: zm.Mat) void {
        zm.storeMat43(&self.matrix, mat_z);
    }
    // pub fn initWithRotY(x: f32, y: f32, z: f32, angle: f32) Transform {
    //     // f32x4(sc[1], 0.0, -sc[0], 0.0),
    //     // f32x4(0.0, 1.0, 0.0, 0.0),
    //     // f32x4(sc[0], 0.0, sc[1], 0.0),
    //     // f32x4(0.0, 0.0, 0.0, 1.0),
    //     return .{
    //         .matrix = [_]f32{
    //             scale, 0.0,   0.0,
    //             0.0,   scale, 0.0,
    //             0.0,   0.0,   scale,
    //             x,     y,     z,
    //         },
    //     };
    // }
    // pub fn createScalar(scale: f32) Scale {
    //     return .{ .x = scale, .y = scale, .z = scale };
    // }
    // pub fn elems(self: *Scale) *[3]f32 {
    //     return @ptrCast(*[3]f32, &self.x);
    // }
    // pub fn elemsConst(self: *const Scale) *const [3]f32 {
    //     return @ptrCast(*const [3]f32, &self.x);
    // }
    pub fn print(self: Transform, prefix: []const u8) void {
        std.debug.print(
            "{s}\n{d:>7.3} {d:>7.3} {d:>7.3}\n{d:>7.3} {d:>7.3} {d:>7.3}\n{d:>7.3} {d:>7.3} {d:>7.3}\n{d:>7.3} {d:>7.3} {d:>7.3}\n",
            .{
                prefix,
                self.matrix[0],
                self.matrix[1],
                self.matrix[2],
                self.matrix[3],
                self.matrix[4],
                self.matrix[5],
                self.matrix[6],
                self.matrix[7],
                self.matrix[8],
                self.matrix[9],
                self.matrix[10],
                self.matrix[11],
            },
        );
    }
};

pub const Dynamic = struct { // TODO: Replace with empty tag
    dummy: u8 = 0,
};

pub const Velocity = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    pub fn elems(self: *Velocity) *[3]f32 {
        return @as(*[3]f32, @ptrCast(&self.x));
    }
};

// ███╗   ███╗███████╗███████╗██╗  ██╗
// ████╗ ████║██╔════╝██╔════╝██║  ██║
// ██╔████╔██║█████╗  ███████╗███████║
// ██║╚██╔╝██║██╔══╝  ╚════██║██╔══██║
// ██║ ╚═╝ ██║███████╗███████║██║  ██║
// ╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝

pub const SurfaceType = enum {
    @"opaque",
    masked,
};

pub const PBRMaterial = struct {
    base_color: ColorRGB,
    metallic: f32,
    roughness: f32,
    normal_intensity: f32,
    emissive_strength: f32,
    albedo: TextureHandle,
    normal: TextureHandle,
    arm: TextureHandle,
    emissive: TextureHandle,
    surface_type: SurfaceType,

    pub fn init() PBRMaterial {
        return .{
            .base_color = ColorRGB.init(1, 1, 1),
            .roughness = 0.8,
            .metallic = 0,
            .normal_intensity = 1.0,
            .emissive_strength = 1.0,
            .albedo = TextureHandle.nil,
            .normal = TextureHandle.nil,
            .arm = TextureHandle.nil,
            .emissive = TextureHandle.nil,
            .surface_type = .@"opaque",
        };
    }

    pub fn initNoTexture(base_color: ColorRGB, roughness: f32, metallic: f32) PBRMaterial {
        return .{
            .base_color = base_color,
            .roughness = roughness,
            .metallic = metallic,
            .normal_intensity = 1.0,
            .emissive_strength = 1.0,
            .albedo = TextureHandle.nil,
            .normal = TextureHandle.nil,
            .arm = TextureHandle.nil,
            .emissive = TextureHandle.nil,
            .surface_type = .@"opaque",
        };
    }
};

pub const UIImageComponent = struct {
    rect: [4]f32,
    material: UIMaterial,
};

pub const UIMaterial = struct {
    color: [4]f32,
    texture: TextureHandle,
};

pub const StaticMeshComponent = struct {
    mesh_handle: MeshHandle,

    material_count: u32,
    materials: [renderer.sub_mesh_max_count]PBRMaterial,
};

// ███████╗██╗  ██╗██╗   ██╗██████╗  ██████╗ ██╗  ██╗
// ██╔════╝██║ ██╔╝╚██╗ ██╔╝██╔══██╗██╔═══██╗╚██╗██╔╝
// ███████╗█████╔╝  ╚████╔╝ ██████╔╝██║   ██║ ╚███╔╝
// ╚════██║██╔═██╗   ╚██╔╝  ██╔══██╗██║   ██║ ██╔██╗
// ███████║██║  ██╗   ██║   ██████╔╝╚██████╔╝██╔╝ ██╗
// ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝

pub const SkyLightComponent = struct {
    hdri: TextureHandle,
    mesh: MeshHandle,
    intensity: f32,
};

//  ██████╗ █████╗ ███╗   ███╗███████╗██████╗  █████╗
// ██╔════╝██╔══██╗████╗ ████║██╔════╝██╔══██╗██╔══██╗
// ██║     ███████║██╔████╔██║█████╗  ██████╔╝███████║
// ██║     ██╔══██║██║╚██╔╝██║██╔══╝  ██╔══██╗██╔══██║
// ╚██████╗██║  ██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║
//  ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
//

pub const CICamera = struct {
    near: f32,
    far: f32,
    active: bool = false,
    class: u32 = 0,
};

pub const Camera = struct {
    near: f32,
    far: f32,
    fov: f32,
    view: [16]f32 = undefined,
    projection: [16]f32 = undefined,
    view_projection: [16]f32 = undefined,
    frustum_planes: [4][4]f32 = undefined,
    active: bool = false,
    class: u32 = 0,

    pub fn calculateFrustumPlanes(camera: *Camera) void {
        const z_vp = zm.loadMat(camera.view_projection[0..]);

        // Left plane
        camera.frustum_planes[0][0] = z_vp[0][3] + z_vp[0][0];
        camera.frustum_planes[0][1] = z_vp[1][3] + z_vp[1][0];
        camera.frustum_planes[0][2] = z_vp[2][3] + z_vp[2][0];
        camera.frustum_planes[0][3] = z_vp[3][3] + z_vp[3][0];

        // Right plane
        camera.frustum_planes[1][0] = z_vp[0][3] - z_vp[0][0];
        camera.frustum_planes[1][1] = z_vp[1][3] - z_vp[1][0];
        camera.frustum_planes[1][2] = z_vp[2][3] - z_vp[2][0];
        camera.frustum_planes[1][3] = z_vp[3][3] - z_vp[3][0];

        // Top plane
        camera.frustum_planes[2][0] = z_vp[0][3] - z_vp[0][1];
        camera.frustum_planes[2][1] = z_vp[1][3] - z_vp[1][1];
        camera.frustum_planes[2][2] = z_vp[2][3] - z_vp[2][1];
        camera.frustum_planes[2][3] = z_vp[3][3] - z_vp[3][1];

        // Bottom plane
        camera.frustum_planes[3][0] = z_vp[0][3] + z_vp[0][1];
        camera.frustum_planes[3][1] = z_vp[1][3] + z_vp[1][1];
        camera.frustum_planes[3][2] = z_vp[2][3] + z_vp[2][1];
        camera.frustum_planes[3][3] = z_vp[3][3] + z_vp[3][1];

        // TODO(gmodarelli): Figure out what these become when Z is reversed
        // // Near plane
        // camera.frustum_planes[4][0] = z_vp[0][2];
        // camera.frustum_planes[4][1] = z_vp[1][2];
        // camera.frustum_planes[4][2] = z_vp[2][2];
        // camera.frustum_planes[4][3] = z_vp[3][2];

        // // Far plane
        // camera.frustum_planes[5][0] = z_vp[0][3] - z_vp[0][2];
        // camera.frustum_planes[5][1] = z_vp[1][3] - z_vp[1][2];
        // camera.frustum_planes[5][2] = z_vp[2][3] - z_vp[2][2];
        // camera.frustum_planes[5][3] = z_vp[3][3] - z_vp[3][2];

        for (&camera.frustum_planes) |*plane| {
            const length = std.math.sqrt(plane[0] * plane[0] + plane[1] * plane[1] + plane[2] * plane[2]);
            plane[0] = plane[0] / length;
            plane[1] = plane[1] / length;
            plane[2] = plane[2] / length;
            plane[3] = plane[3] / length;
        }
    }

    pub fn isVisible(camera: *const Camera, center: [3]f32, radius: f32) bool {
        for (camera.frustum_planes) |plane| {
            if (distanceToPoint(plane, center) + radius < 0.0) {
                return false;
            }
        }

        return true;
    }

    fn distanceToPoint(plane: [4]f32, point: [3]f32) f32 {
        return plane[0] * point[0] + plane[1] * point[1] + plane[2] * point[2] + plane[3];
    }
};

// ██████╗ ██╗  ██╗██╗   ██╗███████╗██╗ ██████╗███████╗
// ██╔══██╗██║  ██║╚██╗ ██╔╝██╔════╝██║██╔════╝██╔════╝
// ██████╔╝███████║ ╚████╔╝ ███████╗██║██║     ███████╗
// ██╔═══╝ ██╔══██║  ╚██╔╝  ╚════██║██║██║     ╚════██║
// ██║     ██║  ██║   ██║   ███████║██║╚██████╗███████║
// ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝ ╚═════╝╚══════╝

// pub const CIPhysicsBody = struct {
//     mass: f32,
//     shape_type: enum {
//         box,
//         sphere,
//     },

//     box: struct { size: f32 } = undefined,
//     sphere: struct { radius: f32 } = undefined,
// };
pub const PhysicsBody = struct {
    body_id: zphy.BodyId,
};

// ████████╗███████╗██████╗ ██████╗  █████╗ ██╗███╗   ██╗
// ╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║
//    ██║   █████╗  ██████╔╝██████╔╝███████║██║██╔██╗ ██║
//    ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██║██║╚██╗██║
//    ██║   ███████╗██║  ██║██║  ██║██║  ██║██║██║ ╚████║
//    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

pub const TerrainPatchLookup = struct {
    lookup: u16 = undefined,
    // lod: u8 = 0,
};

pub const WorldLoader = struct {
    range: i32 = undefined,
    physics: bool = false,
    props: bool = false,
};

pub const WorldPatch = struct {
    lookup: u32 = undefined,
};

// pub const ComponentData = struct { pos: *Position, vel: *Velocity };

// ██╗     ██╗ ██████╗ ██╗  ██╗████████╗
// ██║     ██║██╔════╝ ██║  ██║╚══██╔══╝
// ██║     ██║██║  ███╗███████║   ██║
// ██║     ██║██║   ██║██╔══██║   ██║
// ███████╗██║╚██████╔╝██║  ██║   ██║
// ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝

pub const DirectionalLightComponent = struct {
    color: ColorRGB,
    intensity: f32,
};

pub const PointLightComponent = struct {
    color: ColorRGB,
    range: f32,
    intensity: f32,
};

// ███████╗███████╗███╗   ███╗
// ██╔════╝██╔════╝████╗ ████║
// █████╗  ███████╗██╔████╔██║
// ██╔══╝  ╚════██║██║╚██╔╝██║
// ██║     ███████║██║ ╚═╝ ██║
// ╚═╝     ╚══════╝╚═╝     ╚═╝

pub const CIFSM = struct {
    state_machine_hash: u64,
};

pub const FSM = struct {
    state_machine_lookup: u16,
    blob_lookup: u64,
};

// ██╗███╗   ██╗██████╗ ██╗   ██╗████████╗
// ██║████╗  ██║██╔══██╗██║   ██║╚══██╔══╝
// ██║██╔██╗ ██║██████╔╝██║   ██║   ██║
// ██║██║╚██╗██║██╔═══╝ ██║   ██║   ██║
// ██║██║ ╚████║██║     ╚██████╔╝   ██║
// ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝    ╚═╝

pub const Input = struct {
    active: bool = false,
    index: u32,
};

pub const Interactor = struct {
    active: bool = false,
    wielded_item_ent_id: ecs.entity_t,
};

// ███████╗██████╗  █████╗ ██╗    ██╗███╗   ██╗
// ██╔════╝██╔══██╗██╔══██╗██║    ██║████╗  ██║
// ███████╗██████╔╝███████║██║ █╗ ██║██╔██╗ ██║
// ╚════██║██╔═══╝ ██╔══██║██║███╗██║██║╚██╗██║
// ███████║██║     ██║  ██║╚███╔███╔╝██║ ╚████║
// ╚══════╝╚═╝     ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═══╝

pub const SpawnPoint = struct {
    active: bool = false,
    id: u64,
};

//  ██████╗ ██╗   ██╗ █████╗ ██╗     ██╗████████╗██╗   ██╗
// ██╔═══██╗██║   ██║██╔══██╗██║     ██║╚══██╔══╝╚██╗ ██╔╝
// ██║   ██║██║   ██║███████║██║     ██║   ██║    ╚████╔╝
// ██║▄▄ ██║██║   ██║██╔══██║██║     ██║   ██║     ╚██╔╝
// ╚██████╔╝╚██████╔╝██║  ██║███████╗██║   ██║      ██║
//  ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝      ╚═╝

pub const Speed = struct {
    value: f32,
};

pub const Health = struct {
    value: f32,
};

pub const Quality = struct {
    name: IdLocal,
    value: f32,
};

pub const Effect = struct {
    name: IdLocal,
    apply_rule: enum {
        to_self,
        to_parent,
        to_child,
    },
};

//  ██████╗██╗████████╗██╗   ██╗
// ██╔════╝██║╚══██╔══╝╚██╗ ██╔╝
// ██║     ██║   ██║    ╚████╔╝
// ██║     ██║   ██║     ╚██╔╝
// ╚██████╗██║   ██║      ██║
//  ╚═════╝╚═╝   ╚═╝      ╚═╝

pub const CompCity = struct {
    next_spawn_time: f32,
    spawn_cooldown: f32,
    caravan_members_to_spawn: i32 = 0,
    closest_cities: [2]ecs.entity_t,
    curr_target_city: ecs.entity_t,
};
pub const CompBanditCamp = struct {
    next_spawn_time: f32,
    spawn_cooldown: f32,
    caravan_members_to_spawn: i32 = 0,
    closest_cities: [2]ecs.entity_t,
    // curr_target_city: ecs.entity_t,
};
pub const CompCaravan = struct {
    start_pos: [3]f32,
    end_pos: [3]f32,
    time_to_arrive: f32,
    time_birth: f32,
    destroy_on_arrival: bool,
};

pub const CompCombatant = struct {
    faction: i32,
};

pub const EnvironmentInfo = struct {
    paused: bool,
    active_camera: ?ecsu.Entity,
    time_multiplier: f32 = 1.0,
    world_time: f32,
    time_of_day_percent: f32,
    sun_height: f32,
    sky_light: ?ecsu.Entity,
    // time_of_day_hour: f32,
    // days_in_year: f32,
    // day: f32,

};

// ██╗    ██╗███████╗ █████╗ ██████╗  ██████╗ ███╗   ██╗
// ██║    ██║██╔════╝██╔══██╗██╔══██╗██╔═══██╗████╗  ██║
// ██║ █╗ ██║█████╗  ███████║██████╔╝██║   ██║██╔██╗ ██║
// ██║███╗██║██╔══╝  ██╔══██║██╔═══╝ ██║   ██║██║╚██╗██║
// ╚███╔███╔╝███████╗██║  ██║██║     ╚██████╔╝██║ ╚████║
//  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═══╝

pub const ProjectileWeapon = struct {
    chambered_projectile: ecs.entity_t = 0,
    cooldown: f32 = 0,
    charge: f32 = 0,
};

pub const Projectile = struct {
    dummy: u8 = 0,
    // chambered_projectile: ecs.entity_t = 0,
};
