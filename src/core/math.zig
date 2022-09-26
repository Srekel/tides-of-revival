const std = @import("std");

pub fn dist3_xz(posA: [3]f32, posB: [3]f32) f32 {
    return std.math.hypot(f32, posA[0] - posB[0], posA[2] - posB[2]);
}
