const zmath = @import("zmath");
const window = @import("window.zig");
const glfw = @import("glfw");

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

pub const Forward = struct {
    x: f32,
    y: f32,
    z: f32,
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

pub const Scale = struct {
    x: f32,
    y: f32,
    z: f32,
    pub fn elems(self: *Scale) *[3]f32 {
        return @ptrCast(*[3]f32, &self.x);
    }
    pub fn elemsConst(self: *const Scale) *const [3]f32 {
        return @ptrCast(*const [3]f32, &self.x);
    }
};

pub const Velocity = struct { x: f32, y: f32, z: f32 };

pub const CIMesh = struct {
    mesh_type: u64,
    basecolor_roughness: ColorRGBRoughness,
};
pub const Mesh = struct {
    mesh_index: u64,
    basecolor_roughness: ColorRGBRoughness,
};

pub const CICamera = struct {
    lookat: Position,
    near: f32,
    far: f32,
    window: glfw.Window,
};
pub const Camera = struct {
    near: f32,
    far: f32,
    pitch: f32 = 0,
    yaw: f32 = 0,
    world_to_view: [16]f32 = undefined,
    view_to_clip: [16]f32 = undefined,
    world_to_clip: [16]f32 = undefined,
    window: glfw.Window,
    cursor_known: glfw.Window.CursorPos = .{ .xpos = 0.0, .ypos = 0.0 },
};

pub const NOCOMP = struct {};
pub const ComponentData = struct { pos: *Position, vel: *Velocity };
