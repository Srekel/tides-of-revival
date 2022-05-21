pub const Velocity = struct { x: f32, y: f32, z: f32 };
pub const Position = struct { x: f32, y: f32, z: f32 };
pub const Acceleration = struct { x: f32, y: f32, z: f32 };

pub const ComponentData = struct { pos: *Position, vel: *Velocity };
pub const AccelComponentData = struct { pos: *Position, vel: *Velocity, accel: *Acceleration };
