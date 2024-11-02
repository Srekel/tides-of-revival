const std = @import("std");

const types = @import("../types.zig");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

const jcv_point = c_cpp_nodes.jcv_point;
const tph_poisson_real = c_cpp_nodes.tph_poisson_real;
const tph_poisson_args = c_cpp_nodes.tph_poisson_args;
const tph_poisson_allocator = c_cpp_nodes.tph_poisson_allocator;
const tph_poisson_sampling = c_cpp_nodes.tph_poisson_sampling;
const tph_poisson_create = c_cpp_nodes.tph_poisson_create;
const tph_poisson_get_samples = c_cpp_nodes.tph_poisson_get_samples;
const tph_poisson_destroy = c_cpp_nodes.tph_poisson_destroy;
const TPH_POISSON_SUCCESS = c_cpp_nodes.TPH_POISSON_SUCCESS;

pub fn generate_points(size: types.Size2D, radius: tph_poisson_real, seed: u64, points: *std.ArrayList(types.Vec2)) void {
    const bounds_min = [_]tph_poisson_real{ 0, 0 };
    const bounds_max = [_]tph_poisson_real{ @floatFromInt(size.width), @floatFromInt(size.height) };
    const args = tph_poisson_args{
        .bounds_min = &bounds_min,
        .bounds_max = &bounds_max,
        .seed = seed,
        .radius = radius,
        .ndims = 2,
        .max_sample_attempts = 30,
    };
    const allocator: ?*tph_poisson_allocator = null;

    var sampling = tph_poisson_sampling{
        .internal = null,
        .nsamples = 0,
        .ndims = 0,
    };
    const ret = tph_poisson_create(&args, allocator, &sampling);
    std.debug.assert(ret == TPH_POISSON_SUCCESS);

    const samples = tph_poisson_get_samples(&sampling);
    std.debug.assert(samples != null);

    points.ensureTotalCapacity(@intCast(sampling.nsamples)) catch unreachable;
    points.appendSliceAssumeCapacity(types.castSliceToSlice(types.Vec2, samples[0..@intCast(sampling.nsamples * 2)]));
    tph_poisson_destroy(&sampling);
}
