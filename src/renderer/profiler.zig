const std = @import("std");

const graphics = @import("zforge").graphics;
const IdLocal = @import("../core/core.zig").IdLocal;
const Renderer = @import("renderer.zig").Renderer;
const util = @import("../util.zig");

// Ported from: https://github.com/TheRealMJP/DXRPathTracer/blob/master/SampleFramework12/v1.02/Graphics/Profiler.h

pub const Profiler = struct {
    const profiles_max_count: usize = 64;
    const invalid_profile_index: usize = std.math.maxInt(usize);

    renderer: *Renderer,
    timer: std.time.Timer,
    profiles: std.ArrayList(ProfileData),
    cpu_profiles: std.ArrayList(ProfileData),
    query_pools: [Renderer.data_buffer_count][*c]graphics.QueryPool,

    pub fn init(self: *Profiler, renderer: *Renderer, allocator: std.mem.Allocator) void {
        self.profiles = std.ArrayList(ProfileData).init(allocator);
        self.cpu_profiles = std.ArrayList(ProfileData).init(allocator);
        self.renderer = renderer;
        self.timer = std.time.Timer.start() catch unreachable;

        for (0..Renderer.data_buffer_count) |frame_index| {
            const query_pool_desc = graphics.QueryPoolDesc{
                .pName = "GPU Profiler",
                .mType = .QUERY_TYPE_TIMESTAMP,
                .mQueryCount = profiles_max_count,
                .mNodeIndex = 0,
            };

            graphics.initQueryPool(self.renderer.renderer, @ptrCast(&query_pool_desc), &self.query_pools[frame_index]);
        }
    }

    pub fn shutdown(self: *Profiler) void {
        for (0..Renderer.data_buffer_count) |frame_index| {
            graphics.exitQueryPool(self.renderer.renderer, self.query_pools[frame_index]);
        }
        self.profiles.deinit();
        self.cpu_profiles.deinit();
    }

    pub fn startProfile(self: *Profiler, cmd_list: [*c]graphics.Cmd, name: []const u8) usize {
        const id = IdLocal.init(name);

        var profile_index: usize = invalid_profile_index;
        for (self.profiles.items, 0..) |profile, index| {
            if (profile.id.hash == id.hash) {
                profile_index = index;
                break;
            }
        }

        if (profile_index == invalid_profile_index) {
            std.debug.assert(self.profiles.items.len < profiles_max_count);
            profile_index = self.profiles.items.len;

            var profile = std.mem.zeroes(ProfileData);
            profile.id = id;
            util.memcpy(&profile.name, @ptrCast(&name.ptr), name.len, .{});
            @memset(profile.time_samples[0..], 0);
            self.profiles.append(profile) catch unreachable;
        }

        var profile_data = &self.profiles.items[profile_index];
        std.debug.assert(profile_data.query_started == false);
        std.debug.assert(profile_data.query_finished == false);
        profile_data.active = true;
        profile_data.query_started = true;

        // Insert the start timestamp
        const query_desc = graphics.QueryDesc{
            .mIndex = @intCast(profile_index),
        };

        graphics.cmdBeginDebugMarker(cmd_list, 0.1, 0.8, 0.1, @ptrCast(name[0..]));
        graphics.cmdBeginQuery(cmd_list, self.query_pools[self.renderer.frame_index], @constCast(&query_desc));

        return profile_index;
    }

    pub fn endProfile(self: *Profiler, cmd_list: [*c]graphics.Cmd, profile_index: usize) void {
        std.debug.assert(profile_index < self.profiles.items.len);

        var profile_data = &self.profiles.items[profile_index];
        std.debug.assert(profile_data.query_started == true);
        std.debug.assert(profile_data.query_finished == false);

        // Insert the end timestamp
        const query_desc = graphics.QueryDesc{
            .mIndex = @intCast(profile_index),
        };
        graphics.cmdEndQuery(cmd_list, self.query_pools[self.renderer.frame_index], @constCast(&query_desc));

        // Resolve the data
        graphics.cmdResolveQuery(cmd_list, self.query_pools[self.renderer.frame_index], query_desc.mIndex, 1);
        graphics.cmdEndDebugMarker(cmd_list);

        profile_data.query_started = false;
        profile_data.query_finished = true;
    }

    pub fn startCpuProfile(self: *Profiler, name: []const u8) usize {
        const id = IdLocal.init(name);

        var profile_index: usize = invalid_profile_index;
        for (self.cpu_profiles.items, 0..) |profile, index| {
            if (profile.id.hash == id.hash) {
                profile_index = index;
                break;
            }
        }

        if (profile_index == invalid_profile_index) {
            std.debug.assert(self.cpu_profiles.items.len < profiles_max_count);
            profile_index = self.cpu_profiles.items.len;

            var profile = std.mem.zeroes(ProfileData);
            profile.id = id;
            util.memcpy(&profile.name, @ptrCast(&name.ptr), name.len, .{});
            @memset(profile.time_samples[0..], 0);
            self.cpu_profiles.append(profile) catch unreachable;
        }

        var profile_data = &self.cpu_profiles.items[profile_index];
        std.debug.assert(profile_data.query_started == false);
        std.debug.assert(profile_data.query_finished == false);
        profile_data.active = true;
        profile_data.query_started = true;
        profile_data.start_time = self.timer.read();

        return profile_index;
    }

    pub fn endCpuProfile(self: *Profiler, profile_index: usize) void {
        std.debug.assert(profile_index < self.cpu_profiles.items.len);

        var profile_data = &self.cpu_profiles.items[profile_index];
        std.debug.assert(profile_data.query_started == true);
        std.debug.assert(profile_data.query_finished == false);

        profile_data.end_time = self.timer.read();
        profile_data.query_started = false;
        profile_data.query_finished = true;
    }

    pub fn endFrame(self: *Profiler) void {
        var timestamp_frequency: f64 = 0;
        graphics.getTimestampFrequency(self.renderer.graphics_queue, @ptrCast(&timestamp_frequency));

        for (self.profiles.items, 0..) |*profile, profile_index| {
            profile.query_finished = false;

            var query_data = std.mem.zeroes(graphics.QueryData);
            graphics.getQueryData(self.renderer.renderer, self.query_pools[self.renderer.frame_index], @intCast(profile_index), @ptrCast(&query_data));

            var time: f64 = 0.0;
            const start_time = query_data.__union_field1.__struct_field3.mBeginTimestamp;
            const end_time = query_data.__union_field1.__struct_field3.mEndTimestamp;
            if (end_time > start_time) {
                const delta = end_time - start_time;
                time = @as(f64, @floatFromInt(delta)) / timestamp_frequency * 1000.0;
            }

            profile.time_samples[profile.current_sample] = time;
            profile.current_sample = (profile.current_sample + 1) % ProfileData.filter_size;

            profile.active = false;
        }

        for (self.cpu_profiles.items) |*profile| {
            profile.query_finished = false;

            const time: f64 = @as(f64, @floatFromInt(profile.end_time - profile.start_time)) / std.time.ns_per_ms;

            profile.time_samples[profile.current_sample] = time;
            profile.current_sample = (profile.current_sample + 1) % ProfileData.filter_size;

            profile.active = false;
        }
    }
};

pub const ProfileData = struct {
    pub const filter_size: usize = 64;

    name: [256]u8,
    id: IdLocal,
    query_started: bool,
    query_finished: bool,
    active: bool,
    start_time: u64 = 0,
    end_time: u64 = 0,
    time_samples: [filter_size]f64 = undefined,
    current_sample: usize,
};
