const std = @import("std");

pub fn dist3_xz(pos_a: anytype, pos_b: anytype) std.meta.Elem(@TypeOf(pos_a)) {
    return std.math.hypot(
        std.meta.Elem(@TypeOf(pos_a)),
        pos_a[0] - pos_b[0],
        pos_a[2] - pos_b[2],
    );
}

pub fn easeInOutQuad(t: f32) f32 {
    return if (t < 0.5) 2 * t * t else 1 - std.math.pow(f32, -2 * t + 2, 2) / 2;
}
