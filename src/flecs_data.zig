const std = @import("std");
const window = @import("window.zig");
const zglfw = @import("zglfw");
const zphy = @import("zphysics");
const zm = @import("zmath");
const zmesh = @import("zmesh");
const flecs = @import("flecs");

// pub const GameContext = struct {
//     constvars: std.AutoHashMap(IdLocal, []const u8),
//     vars: std.AutoHashMap(IdLocal, []u8),
//     fn getConst(self: GameContext, comptime T: type, id: IdLocal) *const T {

//     }
// };

const IdLocal = @import("variant.zig").IdLocal;
pub const NOCOMP = struct {};

pub const ColorRGB = struct {
    r: f32,
    g: f32,
    b: f32,
    pub fn init(r: f32, g: f32, b: f32) ColorRGB {
        return .{ .r = r, .g = g, .b = b };
    }
    pub fn elems(self: *ColorRGB) *[3]f32 {
        return @ptrCast(*[3]f32, &self.r);
    }
    pub fn elemsConst(self: *const ColorRGB) *const [3]f32 {
        return @ptrCast(*const [3]f32, &self.r);
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
        return @ptrCast(*[3]f32, &self.x);
    }
    pub fn elemsConst(self: *const Position) *const [3]f32 {
        return @ptrCast(*const [3]f32, &self.x);
    }
};

pub const Forward = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 1,
    pub fn elems(self: *Forward) *[3]f32 {
        return @ptrCast(*[3]f32, &self.x);
    }
    pub fn elemsConst(self: *const Forward) *const [3]f32 {
        return @ptrCast(*const [3]f32, &self.x);
    }
};

pub const Rotation = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
    pub fn elems(self: *Rotation) *[4]f32 {
        return @ptrCast(*[4]f32, &self.x);
    }
    pub fn elemsConst(self: *const Rotation) *const [4]f32 {
        return @ptrCast(*const [4]f32, &self.x);
    }
};

pub const EulerRotation = struct {
    pitch: f32 = 0,
    yaw: f32 = 0,
    roll: f32 = 0,
    pub fn init(pitch: f32, yaw: f32, roll: f32) EulerRotation {
        return .{ .pitch = pitch, .yaw = yaw, .roll = roll };
    }
    pub fn elems(self: *EulerRotation) *[4]f32 {
        return @ptrCast(*[3]f32, &self.x);
    }
    pub fn elemsConst(self: *const EulerRotation) *const [4]f32 {
        return @ptrCast(*const [3]f32, &self.x);
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
        return @ptrCast(*[3]f32, &self.x);
    }
    pub fn elemsConst(self: *const Scale) *const [3]f32 {
        return @ptrCast(*const [3]f32, &self.x);
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

    pub fn getPos00(self: Transform) [3]f32 {
        return self.matrix[9..].*;
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

    pub fn getRotQuaternion(self: Transform) [3]f32 {
        const mat = zm.loadMat43(&self.matrix);
        const quat = zm.matToQuat(mat);
        var out: f32[4] = undefined;
        zm.storeArr4(&out, quat);
        return out;
    }

    pub fn setScale(self: *Transform, scale: [3]f32) void {
        self.matrix[0] = scale[0];
        self.matrix[4] = scale[1];
        self.matrix[8] = scale[2];
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
};

// ███╗   ███╗███████╗███████╗██╗  ██╗
// ████╗ ████║██╔════╝██╔════╝██║  ██║
// ██╔████╔██║█████╗  ███████╗███████║
// ██║╚██╔╝██║██╔══╝  ╚════██║██╔══██║
// ██║ ╚═╝ ██║███████╗███████║██║  ██║
// ╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝

pub const CIShapeMeshDefinition = struct {
    id: IdLocal,
    shape: zmesh.Shape,
};
pub const ShapeMeshDefinition = struct {
    id: IdLocal,
    mesh_index: u64,
};

pub const CIShapeMeshInstance = struct {
    id: u64,
    basecolor_roughness: ColorRGBRoughness,
};
pub const ShapeMeshInstance = struct {
    mesh_index: u64,
    basecolor_roughness: ColorRGBRoughness,
};

pub const CICamera = struct {
    near: f32,
    far: f32,
    window: *zglfw.Window,
    active: bool = false,
    class: u32 = 0,
};

pub const Camera = struct {
    near: f32,
    far: f32,
    world_to_view: [16]f32 = undefined,
    view_to_clip: [16]f32 = undefined,
    world_to_clip: [16]f32 = undefined,
    window: *zglfw.Window,
    active: bool = false,
    class: u32 = 0,
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

pub const Light = struct {
    radiance: ColorRGB,
    range: f32,
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
    wielded_item_ent_id: flecs.EntityId,
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
    closest_cities: [2]flecs.EntityId,
    curr_target_city: flecs.EntityId,
};
pub const CompBanditCamp = struct {
    next_spawn_time: f32,
    spawn_cooldown: f32,
    caravan_members_to_spawn: i32 = 0,
    closest_cities: [2]flecs.EntityId,
    // curr_target_city: flecs.EntityId,
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
    world_time: f32,
    time_of_day_percent: f32,
    sun_height: f32,
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

const ProjectileWeapon = struct {
    chambered_projectile: flecs.EntityId,
};
