const std = @import("std");
const assert = std.debug.assert;
const zwin32 = @import("zwin32");
const d3d12 = zwin32.d3d12;
const hrPanicOnFail = zwin32.hrPanicOnFail;
const zd3d12 = @import("zd3d12");

pub const ProfileData = struct {
    pub const filter_size: u64 = 64;

    name: []const u8 = undefined,
    query_started: bool = false,
    query_finished: bool = false,
    active: bool = false,
    start_time: u64,
    end_time: u64,

    time_samples: [filter_size]f64 = undefined,
    current_sample: u64 = 0,
    avg_time: f64,
    max_time: f64,
};

pub const Profiler = struct {
    pub const max_profiles: u64 = 64;

    profiles: std.ArrayList(ProfileData),
    num_profiles: u64,
    query_heap: *d3d12.IQueryHeap,
    readback_buffer: *d3d12.IResource,

    pub fn init(allocator: std.mem.Allocator, gctx: *zd3d12.GraphicsContext) !Profiler {
        const query_heap = blk: {
            const query_heap_desc = d3d12.QUERY_HEAP_DESC{
                .Type = .TIMESTAMP,
                .Count = max_profiles * 2,
                .NodeMask = 0,
            };

            var query_heap: *d3d12.IQueryHeap = undefined;
            hrPanicOnFail(gctx.device.CreateQueryHeap(&query_heap_desc, &d3d12.IID_IQueryHeap, @as(*?*anyopaque, @ptrCast(&query_heap))));
            break :blk query_heap;
        };

        const readback_buffer = blk: {
            const readback_buffer_desc = d3d12.RESOURCE_DESC.initBuffer(max_profiles * zd3d12.GraphicsContext.max_num_buffered_frames * 2 * @sizeOf(u64));
            const readback_heap_props = d3d12.HEAP_PROPERTIES.initType(.READBACK);

            var readback_buffer: *d3d12.IResource = undefined;
            hrPanicOnFail(gctx.device.CreateCommittedResource(
                &readback_heap_props,
                .{},
                &readback_buffer_desc,
                .{ .COPY_DEST = true },
                null,
                &d3d12.IID_IResource,
                @as(*?*anyopaque, @ptrCast(&readback_buffer)),
            ));
            break :blk readback_buffer;
        };

        var profiles = std.ArrayList(ProfileData).init(allocator);
        profiles.resize(max_profiles * zd3d12.GraphicsContext.max_num_buffered_frames * 2) catch unreachable;

        return Profiler{
            .profiles = profiles,
            .num_profiles = 0,
            .query_heap = query_heap,
            .readback_buffer = readback_buffer,
        };
    }

    pub fn deinit(self: *Profiler) void {
        _ = self.readback_buffer.Release();
        _ = self.query_heap.Release();
        self.profiles.deinit();
    }

    pub fn startProfile(self: *Profiler, cmdlist: *d3d12.IGraphicsCommandList6, name: []const u8) u64 {
        var profile_index: u64 = 0xffff_ffff_ffff_ffff;
        var i: u64 = 0;
        while (i < self.num_profiles) : (i += 1) {
            if (std.mem.eql(u8, name, self.profiles.items[i].name)) {
                profile_index = i;
                break;
            }
        }

        if (profile_index == 0xffff_ffff_ffff_ffff) {
            assert(self.num_profiles < Profiler.max_profiles);
            profile_index = self.num_profiles;
            self.num_profiles += 1;
            self.profiles.items[profile_index].name = name;
        }

        var profile_data = &self.profiles.items[profile_index];
        assert(profile_data.query_started == false);
        assert(profile_data.query_finished == false);
        profile_data.active = true;

        // Insert the start timestamp
        const start_query_index: u32 = @as(u32, @intCast(profile_index * 2));
        cmdlist.EndQuery(self.query_heap, .TIMESTAMP, start_query_index);

        profile_data.query_started = true;
        profile_data.current_sample = 0;

        return profile_index;
    }

    pub fn endProfile(self: *Profiler, cmdlist: *d3d12.IGraphicsCommandList6, index: u64, current_frame_index: u32) void {
        assert(index < self.num_profiles);

        var profile_data = &self.profiles.items[index];
        assert(profile_data.query_started == true);
        assert(profile_data.query_finished == false);

        // Insert the end timestamp
        const start_query_index: u32 = @as(u32, @intCast(index * 2));
        const end_query_index = start_query_index + 1;
        cmdlist.EndQuery(self.query_heap, .TIMESTAMP, end_query_index);

        // Resolve the data
        const dest_offset: u64 = ((current_frame_index * Profiler.max_profiles * 2) + start_query_index) * @sizeOf(u64);
        cmdlist.ResolveQueryData(self.query_heap, .TIMESTAMP, start_query_index, 2, self.readback_buffer, dest_offset);

        profile_data.query_started = false;
        profile_data.query_finished = true;
    }

    pub fn endFrame(self: *Profiler, queue: *d3d12.ICommandQueue, current_frame_index: u32) void {
        var gpu_frequency: u64 = 0;
        hrPanicOnFail(queue.GetTimestampFrequency(&gpu_frequency));

        var readback_buffer_mapping: [*]u8 = undefined;
        hrPanicOnFail(self.readback_buffer.Map(
            0,
            null,
            @as(*?*anyopaque, @ptrCast(&readback_buffer_mapping)),
        ));
        var frame_query_data = @as([*]u64, @ptrCast(@alignCast(readback_buffer_mapping)));

        var i: u64 = 0;
        while (i < self.num_profiles) : (i += 1) {
            self.updateProfile(i, gpu_frequency, current_frame_index, frame_query_data);
        }

        self.readback_buffer.Unmap(0, null);
    }

    fn updateProfile(self: *Profiler, profile_index: u64, gpu_frequency: u64, current_frame_index: u32, frame_query_data: [*]u64) void {
        var profile = &self.profiles.items[profile_index];
        profile.query_finished = false;
        var time: f64 = 0.0;

        // Get the query data
        const start_time_index = current_frame_index * Profiler.max_profiles * 2 + profile_index * 2;
        const end_time_index = start_time_index + 1;
        const start_time = frame_query_data[start_time_index];
        const end_time = frame_query_data[end_time_index];

        if (end_time > start_time) {
            const delta: f64 = @as(f64, @floatFromInt(end_time - start_time));
            const frequency: f64 = @as(f64, @floatFromInt(gpu_frequency));
            time = (delta / frequency) * 1000.0;
        }

        profile.time_samples[profile.current_sample] = time;
        profile.current_sample = (profile.current_sample + 1) % ProfileData.filter_size;

        var max_time: f64 = 0.0;
        var avg_time: f64 = 0.0;
        var avg_time_samples: u64 = 0;
        var i: u64 = 0;
        while (i < ProfileData.filter_size) : (i += 1) {
            if (profile.time_samples[i] <= 0.0) {
                continue;
            }

            max_time = @max(profile.time_samples[i], max_time);
            avg_time += profile.time_samples[i];
            avg_time_samples += 1;
        }

        if (avg_time_samples > 0) {
            avg_time /= @as(f64, @floatFromInt(avg_time_samples));
        }

        profile.avg_time = avg_time;
        profile.max_time = max_time;

        profile.active = false;
    }
};
