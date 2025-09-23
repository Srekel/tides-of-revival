const std = @import("std");
const zphy = @import("zphysics");
const zm = @import("zmath");
const ecs = @import("zflecs");
const config = @import("../config/config.zig");
const window = @import("../renderer/window.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const renderer = @import("../renderer/renderer.zig");
const geometry = @import("../renderer/geometry.zig");
const LegacyMeshHandle = renderer.LegacyMeshHandle;
const TextureHandle = renderer.TextureHandle;

pub fn registerComponents(ecsu_world: ecsu.World) void {
    const ecs_world = ecsu_world.world;
    ecs.TAG(ecs_world, NOCOMP);
    ecs.TAG(ecs_world, LocalSpace);
    ecs.TAG(ecs_world, WorldSpace);
    ecs.TAG(ecs_world, SettlementEnemy);
    ecs.COMPONENT(ecs_world, Locomotion);
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
    ecs.COMPONENT(ecs_world, LodGroup);
    ecs.COMPONENT(ecs_world, Renderable);
    ecs.COMPONENT(ecs_world, Water);
    ecs.COMPONENT(ecs_world, SkyLight);
    ecs.COMPONENT(ecs_world, UIImage);
    ecs.COMPONENT(ecs_world, Camera);
    // ecs.COMPONENT(ecs_world, CIPhysicsBody);
    ecs.COMPONENT(ecs_world, PhysicsBody);
    ecs.COMPONENT(ecs_world, TerrainPatchLookup);
    ecs.COMPONENT(ecs_world, WorldLoader);
    ecs.COMPONENT(ecs_world, WorldPatch);
    // ecs.COMPONENT(ecs_world, ComponentData);
    ecs.COMPONENT(ecs_world, DirectionalLight);
    ecs.COMPONENT(ecs_world, PointLight);
    ecs.COMPONENT(ecs_world, Input);
    ecs.COMPONENT(ecs_world, Interactor);
    ecs.COMPONENT(ecs_world, SpawnPoint);
    ecs.COMPONENT(ecs_world, Health);
    ecs.COMPONENT(ecs_world, Speed);
    ecs.COMPONENT(ecs_world, Quality);
    ecs.COMPONENT(ecs_world, Effect);
    ecs.COMPONENT(ecs_world, Script);
    ecs.COMPONENT(ecs_world, Settlement);
    ecs.COMPONENT(ecs_world, EnvironmentInfo);
    ecs.COMPONENT(ecs_world, ProjectileWeapon);
    ecs.COMPONENT(ecs_world, Projectile);
    ecs.COMPONENT(ecs_world, Journey);
    FSM_PC = ecs.new_entity(ecs_world, config.FSM_PC.toCString());
    FSM_PC_Idle = ecs.new_entity(ecs_world, config.FSM_PC_Idle.toCString());
    FSM_CAM = ecs.new_entity(ecs_world, config.FSM_CAM.toCString());
    FSM_CAM_Fps = ecs.new_entity(ecs_world, config.FSM_CAM_Fps.toCString());
    FSM_CAM_Freefly = ecs.new_entity(ecs_world, config.FSM_CAM_Freefly.toCString());
    FSM_ENEMY = ecs.new_entity(ecs_world, config.FSM_ENEMY.toCString());
    FSM_ENEMY_Idle = ecs.new_entity(ecs_world, config.FSM_ENEMY_Idle.toCString());
    FSM_ENEMY_Slime = ecs.new_entity(ecs_world, config.FSM_ENEMY_Slime.toCString());
    ecs.add_id(ecs_world, FSM_PC, ecs.Union);
    ecs.add_id(ecs_world, FSM_CAM, ecs.Union);
    ecs.add_id(ecs_world, FSM_ENEMY, ecs.Union);
}

pub var FSM_PC: ecs.entity_t = undefined;
pub var FSM_PC_Idle: ecs.entity_t = undefined;
pub var FSM_CAM: ecs.entity_t = undefined;
pub var FSM_CAM_Fps: ecs.entity_t = undefined;
pub var FSM_CAM_Freefly: ecs.entity_t = undefined;
pub var FSM_ENEMY: ecs.entity_t = undefined;
pub var FSM_ENEMY_Idle: ecs.entity_t = undefined;
pub var FSM_ENEMY_Slime: ecs.entity_t = undefined;

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
        return initFromEuler(std.math.degreesToRadians(pitch), std.math.degreesToRadians(yaw), std.math.degreesToRadians(roll));
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
    inv_matrix: [12]f32 = undefined,

    pub fn init(x: f32, y: f32, z: f32) Transform {
        var transform: Transform = undefined;
        transform.matrix = [_]f32{
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0,
            x,   y,   z,
        };
        transform.updateInverseMatrix();
        return transform;
    }

    pub fn initFromPosition(pos: Position) Transform {
        var transform: Transform = undefined;
        transform.matrix = [_]f32{
            1.0,   0.0,   0.0,
            0.0,   1.0,   0.0,
            0.0,   0.0,   1.0,
            pos.x, pos.y, pos.z,
        };
        transform.updateInverseMatrix();
        return transform;
    }

    pub fn initWithScale(x: f32, y: f32, z: f32, scale: f32) Transform {
        var transform: Transform = undefined;
        transform.matrix = [_]f32{
            scale, 0.0,   0.0,
            0.0,   scale, 0.0,
            0.0,   0.0,   scale,
            x,     y,     z,
        };
        transform.updateInverseMatrix();
        return transform;
    }

    pub fn initWithQuaternion(quat: [4]f32) Transform {
        const z_rotation_matrix = zm.matFromQuat(zm.Quat{ quat[0], quat[1], quat[2], quat[3] });
        var transform = Transform{};
        zm.storeMat43(&transform.matrix, z_rotation_matrix);
        transform.updateInverseMatrix();
        return transform;
    }

    pub fn initTRSDegrees(translation: [3]f32, rotation: [3]f32, scale: [3]f32) Transform {
        const translation_z = zm.translation(translation[0], translation[1], translation[2]);
        const rotation_z = zm.matFromQuat(zm.quatFromRollPitchYaw(std.math.degreesToRadians(rotation[0]), std.math.degreesToRadians(rotation[1]), std.math.degreesToRadians(rotation[2])));
        const scale_z = zm.scaling(scale[0], scale[1], scale[2]);

        const trs_z = zm.mul(scale_z, zm.mul(rotation_z, translation_z));
        var transform = Transform{};
        zm.storeMat43(&transform.matrix, trs_z);
        return transform;
    }

    pub fn getPos00(self: Transform) [3]f32 {
        return self.matrix[9..].*;
    }

    pub fn getPos(self: Transform) []const f32 {
        return self.matrix[9..];
    }

    pub fn setPos(self: *Transform, pos: [3]f32) void {
        self.matrix[9..].* = pos;
        self.updateInverseMatrix();
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

        self.updateInverseMatrix();
    }

    pub fn asZM(self: *const Transform) zm.Mat {
        return zm.loadMat43(&self.matrix);
    }

    pub fn fromZM(self: *Transform, mat_z: zm.Mat) void {
        zm.storeMat43(&self.matrix, mat_z);
        self.updateInverseMatrix();
    }

    pub fn updateInverseMatrix(self: *Transform) void {
        const z_matrix = self.asZM();
        const z_inv_matrix = zm.inverse(z_matrix);
        zm.storeMat43(&self.inv_matrix, z_inv_matrix);
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

pub const UIImage = struct {
    rect: [4]f32,
    material: UIMaterial,
};

pub const UIMaterial = struct {
    color: [4]f32,
    texture: TextureHandle,
};

pub const StaticMesh = struct {
    mesh_handle: LegacyMeshHandle,
    materials: std.ArrayList(IdLocal),
};

pub const LodGroup = struct {
    lod_count: u32,
    lods: [geometry.mesh_lod_max_count]StaticMesh,
};

pub const Renderable = struct {
    id: IdLocal,
};

pub const Water = struct {
    mesh_handle: LegacyMeshHandle,
};

// ███████╗██╗  ██╗██╗   ██╗██████╗  ██████╗ ██╗  ██╗
// ██╔════╝██║ ██╔╝╚██╗ ██╔╝██╔══██╗██╔═══██╗╚██╗██╔╝
// ███████╗█████╔╝  ╚████╔╝ ██████╔╝██║   ██║ ╚███╔╝
// ╚════██║██╔═██╗   ╚██╔╝  ██╔══██╗██║   ██║ ██╔██╗
// ███████║██║  ██╗   ██║   ██████╔╝╚██████╔╝██╔╝ ██╗
// ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝

pub const SkyLight = struct {
    hdri: TextureHandle,
    intensity: f32,
};

//  ██████╗ █████╗ ███╗   ███╗███████╗██████╗  █████╗
// ██╔════╝██╔══██╗████╗ ████║██╔════╝██╔══██╗██╔══██╗
// ██║     ███████║██╔████╔██║█████╗  ██████╔╝███████║
// ██║     ██╔══██║██║╚██╔╝██║██╔══╝  ██╔══██╗██╔══██║
// ╚██████╗██║  ██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║
//  ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
//

pub const Camera = struct {
    near: f32,
    far: f32,
    fov: f32,
    view: [16]f32 = undefined,
    projection: [16]f32 = undefined,
    projection_standard: [16]f32 = undefined,
    view_projection: [16]f32 = undefined,
    view_projection_standard: [16]f32 = undefined,
    frustum_planes: [4][4]f32 = undefined,
    active: bool = false,
    class: u32 = 0,

    pub fn create(near: f32, far: f32, fov: f32, active: bool, class: u32) Camera {
        return Camera{
            .near = near,
            .far = far,
            .fov = fov,
            .active = active,
            .class = class,
        };
    }

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
        return plane[0] * point[0] + plane[1] * point[1] + plane[2] * point[2] + plane[3] * plane[3];
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
    shape_opt: ?*zphy.Shape,
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
    navmesh: bool = false,
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

pub const DirectionalLight = struct {
    color: ColorRGB,
    intensity: f32,
    shadow_range: f32,
};

pub const PointLight = struct {
    color: ColorRGB,
    range: f32,
    intensity: f32,
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

pub const Script = struct {
    script: *ecs.script_t,
};

pub const Settlement = struct {
    level: i32 = 1,
    safety: i32 = 0,
};

pub const SettlementEnemy = struct {};

// pub const CompCity = struct {
//     next_spawn_time: f32,
//     spawn_cooldown: f32,
//     caravan_members_to_spawn: i32 = 0,
//     closest_cities: [2]ecs.entity_t,
//     curr_target_city: ecs.entity_t,
// };
// pub const CompBanditCamp = struct {
//     next_spawn_time: f32,
//     spawn_cooldown: f32,
//     caravan_members_to_spawn: i32 = 0,
//     closest_cities: [2]ecs.entity_t,
//     // curr_target_city: ecs.entity_t,
// };
// pub const CompCaravan = struct {
//     start_pos: [3]f32,
//     end_pos: [3]f32,
//     time_to_arrive: f32,
//     time_birth: f32,
//     destroy_on_arrival: bool,
// };

// pub const CompCombatant = struct {
//     faction: i32,
// };

// ███████╗███╗   ██╗██╗   ██╗
// ██╔════╝████╗  ██║██║   ██║
// █████╗  ██╔██╗ ██║██║   ██║
// ██╔══╝  ██║╚██╗██║╚██╗ ██╔╝
// ███████╗██║ ╚████║ ╚████╔╝
// ╚══════╝╚═╝  ╚═══╝  ╚═══╝

pub const EnvironmentInfo = struct {
    paused: bool,
    active_camera: ?ecsu.Entity,
    player_camera: ?ecsu.Entity,
    time_multiplier: f64 = 1.0,
    journey_time_multiplier: f64 = 1.0,
    world_time: f64,
    time_of_day_percent: f64,
    sun_height: f64,
    sky_light: ?ecsu.Entity,
    sun: ?ecsu.Entity,
    player: ?ecsu.Entity,
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
    cooldown: f64 = 0,
    charge: f32 = 0,
};

pub const Projectile = struct {
    dummy: u8 = 0,
    // chambered_projectile: ecs.entity_t = 0,
};

// ██╗      ██████╗  ██████╗ ██████╗ ███╗   ███╗ ██████╗ ████████╗██╗ ██████╗ ███╗   ██╗
// ██║     ██╔═══██╗██╔════╝██╔═══██╗████╗ ████║██╔═══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
// ██║     ██║   ██║██║     ██║   ██║██╔████╔██║██║   ██║   ██║   ██║██║   ██║██╔██╗ ██║
// ██║     ██║   ██║██║     ██║   ██║██║╚██╔╝██║██║   ██║   ██║   ██║██║   ██║██║╚██╗██║
// ███████╗╚██████╔╝╚██████╗╚██████╔╝██║ ╚═╝ ██║╚██████╔╝   ██║   ██║╚██████╔╝██║ ╚████║
// ╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝ ╚═════╝    ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

pub const Locomotion = struct {
    speed: f32 = 5,
    snap_to_terrain: bool = true,
    align_to_terrain: bool = true,
    target_position: ?[3]f32 = null,
};

pub const Journey = struct {
    target_position: ?[3]f32 = null,
};
