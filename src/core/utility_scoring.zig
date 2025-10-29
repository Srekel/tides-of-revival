const std = @import("std");
const fd = @import("../config/flecs_data.zig");

pub const Curve = [25]f32;

pub const Utility = struct {
    xs: []f32,
    curves: []const Curve,
};

pub fn eval_linear_curve(x_value_0_1: f32, curve_ys: Curve) f32 {
    const value = x_value_0_1 * 24;
    return eval_linear_curve_24(value, curve_ys);
}

pub fn eval_linear_curve_24(x_value_0_24: f32, curve_ys: Curve) f32 {
    const x_before = @floor(x_value_0_24);
    const index1: u8 = @intFromFloat(x_before);
    const index2 = index1 + 1;
    const lerp_t: f32 = (x_value_0_24 - x_before);
    const y_before = curve_ys[index1];
    const y_after = curve_ys[index2];
    const y_value = std.math.lerp(y_before, y_after, lerp_t);
    return y_value;
}

pub fn calc_utility(utility: Utility) f32 {
    var score: f32 = 1;
    for (utility.xs, utility.curves) |x, curve| {
        score *= eval_linear_curve_24(x, curve);
    }
    return score;
}

pub fn best(utilities: []Utility) usize {
    var best_score: f32 = 0;
    var best_index: usize = 0;
    for (utilities, 0..) |utility, index| {
        const score = calc_utility(utility);
        if (score > best_score) {
            best_score = score;
            best_index = index;
        }
    }

    return best_index;
}

pub const curveFunction = *const fn (f_in: f32) f32;
pub const CurveTypes = enum {
    flat,
    linear,
};

pub fn CurveTypeFunction(curve_type: CurveTypes, param1: f32, param2: f32) curveFunction {
    return switch (curve_type) {
        .flat => curve_flat(param1),
        .linear => curve_linear(param1, param2),
    };
}

pub fn curve_flat(param: f32) Curve {
    return [1]f32{param} ** 9;
}

pub fn curve_linear(value_0: f32, value_1: f32) Curve {
    var curve: Curve = undefined;
    for (0..8) |index| {
        const t: f32 = @as(f32, @floatFromInt(index)) / 8.0;
        curve[index] = std.math.lerp(value_0, value_1, t);
    }
    curve[8] = value_1;
    return curve;
}
// pub curves() !void {}
