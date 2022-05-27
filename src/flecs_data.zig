const zmath = @import("zmath");

pub const ColorRGB = struct { r: f32, g: f32, b: f32 };
pub const ColorRGBRoughness = struct { r: f32, g: f32, b: f32, roughness: f32 };
pub const Position = struct {
    x: f32,
    y: f32,
    z: f32,
    pub fn elems(self: *Position) *[3]f32 {
        return @ptrCast(*[3]f32, &self.x);
    }
    pub fn elemsConst(self: *const Position) *const [3]f32 {
        return @ptrCast(*const [3]f32, &self.x);
    }
};
pub const Velocity = struct { x: f32, y: f32, z: f32 };
pub const Acceleration = struct { x: f32, y: f32, z: f32 };

pub const CIMesh = struct {
    mesh_type: u64,
    basecolor_roughness: ColorRGBRoughness,
};
pub const Mesh = struct {
    mesh_index: u64,
    basecolor_roughness: ColorRGBRoughness,
};

pub const NOCOMP = struct {};
pub const ComponentData = struct { pos: *Position, vel: *Velocity };
pub const AccelComponentData = struct { pos: *Position, vel: *Velocity, accel: *Acceleration };
