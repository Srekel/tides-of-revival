const std = @import("std");

const Pool = @import("zpool").Pool;
const IdLocal = @import("../core/core.zig").IdLocal;
const BucketQueue = @import("../core/bucket_queue.zig").BucketQueue;
const AssetManager = @import("../core/asset_manager.zig").AssetManager;
const util = @import("../util.zig");
const config = @import("../config/config.zig");
const debug_server = @import("../network/debug_server.zig");

const DEBUG_LOGGING = false;

const LoD = u4;
const lod_0_patch_size = config.patch_size;
const lod_3_patches_side = config.world_size_x / config.largest_patch_width;
const max_world_size = config.world_size_x;
const max_patch = max_world_size / lod_0_patch_size; // 8k patches
const max_patch_int_bits = 16; // 2**13 = 8k
const max_patch_int = std.meta.Int(.unsigned, max_patch_int_bits);

const max_requesters = 8;
const max_patch_types = 8;
pub const Priority = enum {
    come_on_do_it_do_it_come_on_do_it_now,
    high,
    medium,
    low,

    fn lowerThan(self: Priority, other: Priority) bool {
        return @intFromEnum(self) > @intFromEnum(other);
    }
};

pub const RequesterId = u8;
pub const PatchTypeId = u8;
pub const max_dependencies = 2; // intentially low for testing
const dependency_requester_id = 0;

const PatchRequest = struct {
    requester_id: u64,
    prio: Priority,
};

// ██████╗  █████╗ ████████╗ ██████╗██╗  ██╗██╗      ██████╗  ██████╗ ██╗  ██╗██╗   ██╗██████╗
// ██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║██║     ██╔═══██╗██╔═══██╗██║ ██╔╝██║   ██║██╔══██╗
// ██████╔╝███████║   ██║   ██║     ███████║██║     ██║   ██║██║   ██║█████╔╝ ██║   ██║██████╔╝
// ██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║██║     ██║   ██║██║   ██║██╔═██╗ ██║   ██║██╔═══╝
// ██║     ██║  ██║   ██║   ╚██████╗██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██╗╚██████╔╝██║
// ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝

pub const PatchLookup = struct {
    patch_x: max_patch_int,
    patch_z: max_patch_int,
    lod: LoD,
    patch_type_id: PatchTypeId,

    // comptime {
    //     std.debug.assert(@sizeOf(@This()) == @sizeOf(u32));
    // }
    pub fn eql(self: PatchLookup, other: PatchLookup) bool {
        return std.meta.eql(self, other);
    }

    pub fn getWorldPos(self: PatchLookup) struct { world_x: u32, world_z: u32 } {
        const world_stride = lod_0_patch_size * std.math.pow(u32, 2, self.lod);
        return .{
            .world_x = self.patch_x * world_stride,
            .world_z = self.patch_z * world_stride,
        };
    }
    pub fn format(lookup: PatchLookup, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("PL(({any: >3},{any: >3}), PT{}, LoD{})", .{ lookup.patch_x, lookup.patch_z, lookup.patch_type_id, lookup.lod });
    }
};

// ██████╗  █████╗ ████████╗ ██████╗██╗  ██╗
// ██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║
// ██████╔╝███████║   ██║   ██║     ███████║
// ██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║
// ██║     ██║  ██║   ██║   ╚██████╗██║  ██║
// ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝

pub const PatchStatus = enum {
    not_loaded,
    loaded,
    loaded_empty,
    nonexistent,
};

pub const Patch = struct {
    lookup: PatchLookup,
    patch_x: u32,
    patch_z: u32,
    world_x: u32,
    world_z: u32,
    status: PatchStatus = .not_loaded,
    data: ?[]u8 = null,
    requesters: [max_requesters]PatchRequest = undefined,
    request_count: u8 = 0,
    request_count_dependents: u8 = 0,
    highest_prio: Priority = .low,
    patch_type_id: PatchTypeId,

    pub fn isRequester(self: Patch, requester_id: RequesterId) bool {
        var i_req: u32 = 0;
        while (i_req < self.request_count) : (i_req += 1) {
            const requester = &self.requesters[i_req];
            if (requester.requester_id == requester_id) {
                return true;
            }
        }
        return false;
    }

    pub fn hasRequests(self: Patch) bool {
        return self.request_count > 0 or self.request_count_dependents > 0;
    }

    pub fn addOrUpdateRequester(self: *Patch, requester_id: RequesterId, prio: Priority) void {
        if (requester_id == dependency_requester_id) {
            self.request_count_dependents += 1;
            if (DEBUG_LOGGING) std.log.debug("WPM: Requesting dependency #{} on {}, Pr{}", .{ self.request_count_dependents, self.lookup, @intFromEnum(prio) });
        } else {
            var i_req: u32 = 0;
            while (i_req < self.request_count) : (i_req += 1) {
                var requester = &self.requesters[i_req];
                if (requester.requester_id == requester_id) {
                    if (requester.prio != prio) {
                        requester.prio = prio;
                        self.updatePriority();
                    }

                    return;
                }
            }

            self.requesters[self.request_count].requester_id = requester_id;
            self.requesters[self.request_count].prio = prio;
            self.request_count += 1;
        }

        if (self.highest_prio.lowerThan(prio)) {
            self.highest_prio = prio;
        }
    }

    pub fn removeRequester(self: *Patch, requester_id: RequesterId) void {
        if (requester_id == dependency_requester_id) {
            self.request_count_dependents -= 1;
            if (DEBUG_LOGGING) std.log.debug("WPM: Removing dependency #{} on {}", .{ self.request_count_dependents, self.lookup });
            return;
        }

        var i_req: u32 = 0;
        while (i_req < self.request_count) : (i_req += 1) {
            const requester = &self.requesters[i_req];
            if (requester.requester_id == requester_id) {
                self.request_count -= 1;
                requester.* = self.requesters[self.request_count];

                if (self.request_count_dependents == 0) {
                    // NOTE(Anders): Don't update (i.e. lower) priority when we remove requesters
                    // if we have requests from dependents.
                    // This is because we don't store the priority of dependency requests.
                    self.updatePriority();
                }
                return;
            }
        }

        unreachable;
    }

    fn updatePriority(self: *Patch) void {
        // TODO(Anders): Add support for going down in priority.
        // It's disabled for now as a way to simplify things, plus it's not too bad
        // if something remains a higher priority than what it needs to be.
        // self.highest_prio = Priority.low;

        var i_req: u32 = 0;
        while (i_req < self.request_count) : (i_req += 1) {
            if (self.highest_prio.lowerThan(self.requesters[i_req].prio)) {
                self.highest_prio = self.requesters[i_req].prio;
            }
        }
    }
};

pub const PatchPool = Pool(16, 16, void, struct {
    patch: Patch,
});

pub const PatchHandle = PatchPool.Handle;
pub const PatchQueue = BucketQueue(PatchHandle, Priority);

pub const RequestRectangle = struct {
    x: f32,
    z: f32,
    width: f32,
    height: f32,
};

pub const PatchType = struct {
    id: IdLocal,
    dependenciesFn: ?*const fn (PatchLookup, *[max_dependencies]PatchLookup, PatchTypeContext) []PatchLookup = null,
    loadFn: *const fn (*Patch, PatchTypeContext) void,
};

pub const PatchTypeContext = struct {
    asset_mgr: *AssetManager,
    allocator: std.mem.Allocator,
    world_patch_mgr: *WorldPatchManager,
};

fn debugServerHandle(data: []const u8, allocator: std.mem.Allocator, ctx: *anyopaque) []const u8 {
    _ = data;
    var world_patch_mgr = @as(*WorldPatchManager, @ptrCast(@alignCast(ctx)));

    const buckets = .{
        .bucket0 = world_patch_mgr.bucket_queue.buckets[0].items.len,
        .bucket1 = world_patch_mgr.bucket_queue.buckets[1].items.len,
        .bucket2 = world_patch_mgr.bucket_queue.buckets[2].items.len,
        .current_highest_prio = world_patch_mgr.bucket_queue.current_highest_prio,
    };

    var lods: [4][max_patch * max_patch]u32 = undefined;
    var lods_loaded: [4]u32 = .{ 0, 0, 0, 0 };
    var lods_queued: [4]u32 = .{ 0, 0, 0, 0 };

    for (&lods) |*lod| {
        for (lod) |*p| {
            p.* = 0;
        }
    }

    var live_handles = world_patch_mgr.patch_pool.liveHandles();
    while (live_handles.next()) |patch_handle| {
        // _ = patch_handle;
        const patch: *Patch = world_patch_mgr.patch_pool.getColumnPtrAssumeLive(patch_handle, .patch);
        if (patch.lookup.patch_type_id == 0) {
            const patch_stride = 8 * std.math.pow(u32, 2, 3 - patch.lookup.lod);
            lods[patch.lookup.lod][patch.patch_x + patch.patch_z * patch_stride] = if (patch.status == .loaded) 2 else 1;
            lods_loaded[patch.lookup.lod] += if (patch.status == .loaded) 1 else 0;
            lods_queued[patch.lookup.lod] += if (patch.status == .not_loaded) 1 else 0;
        }
    }

    const output = .{
        .buckets = buckets,
        .lods = lods,
        .lods_loaded = lods_loaded,
        .lods_queued = lods_queued,
    };

    var string = std.ArrayList(u8).init(allocator);
    std.json.stringify(output, .{}, string.writer()) catch unreachable;

    return string.items;
}

// ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗
// ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
// ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝
// ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗
// ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║
// ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝

pub const WorldPatchManager = struct {
    allocator: std.mem.Allocator,
    requesters: std.ArrayList(IdLocal) = undefined,
    patch_types: std.ArrayList(PatchType) = undefined,
    handle_map_by_lookup: std.AutoHashMap(PatchLookup, PatchHandle) = undefined,
    patch_pool: PatchPool = undefined,
    bucket_queue: PatchQueue = undefined,
    asset_mgr: *AssetManager = undefined,
    debug_server: debug_server.DebugServer = undefined,

    pub fn create(allocator: std.mem.Allocator, asset_mgr: *AssetManager) *WorldPatchManager {
        var res = allocator.create(WorldPatchManager) catch unreachable;
        res.* = .{
            .allocator = allocator,
            .requesters = std.ArrayList(IdLocal).initCapacity(allocator, max_requesters) catch unreachable,
            .patch_types = std.ArrayList(PatchType).initCapacity(allocator, max_patch_types) catch unreachable,
            .handle_map_by_lookup = std.AutoHashMap(PatchLookup, PatchHandle).init(allocator),
            .patch_pool = PatchPool.initCapacity(allocator, 512) catch unreachable, // temporarily low for testing
            .bucket_queue = PatchQueue.create(allocator, [_]u32{ 8192, 8192, 8192, 8192 }), // temporarily low for testing
            .asset_mgr = asset_mgr,
            .debug_server = debug_server.DebugServer.create(1234, allocator),
        };

        res.debug_server.registerHandler(IdLocal.init("wpm"), debugServerHandle, res);
        const dependent_rid = res.registerRequester(IdLocal.init("dependent"));
        std.debug.assert(dependent_rid == dependency_requester_id);

        return res;
    }

    pub fn destroy(self: *WorldPatchManager) void {
        self.debug_server.stop();
        self.patch_pool.deinit();
    }

    pub fn registerRequester(self: *WorldPatchManager, id: IdLocal) RequesterId {
        const requester_id = @as(u8, @intCast(self.requesters.items.len));
        self.requesters.appendAssumeCapacity(id);
        return requester_id;
    }

    pub fn getRequester(self: *WorldPatchManager, id: IdLocal) RequesterId {
        for (self.requesters.items, 0..) |requester_id, i| {
            if (requester_id.eql(id)) {
                return @as(RequesterId, @intCast(i));
            }
        }
        unreachable;
    }

    pub fn registerPatchType(self: *WorldPatchManager, patch_type: PatchType) PatchTypeId {
        const patch_type_id = @as(u8, @intCast(self.patch_types.items.len));
        self.patch_types.appendAssumeCapacity(patch_type);
        return patch_type_id;
    }

    pub fn getPatchTypeId(self: *WorldPatchManager, id: IdLocal) PatchTypeId {
        for (self.patch_types.items, 0..) |patch_type, i| {
            if (patch_type.id.eql(id)) {
                return @as(PatchTypeId, @intCast(i));
            }
        }
        unreachable;
    }

    pub fn getLookup(world_x: f32, world_z: f32, lod: LoD, patch_type_id: PatchTypeId) PatchLookup {
        const world_stride = lod_0_patch_size * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(lod)));
        const world_x_begin = world_stride * @divFloor(world_x, world_stride);
        const world_z_begin = world_stride * @divFloor(world_z, world_stride);
        const patch_x_begin = @as(u16, @intFromFloat(@divExact(world_x_begin, world_stride)));
        const patch_z_begin = @as(u16, @intFromFloat(@divExact(world_z_begin, world_stride)));
        return PatchLookup{
            .patch_x = patch_x_begin,
            .patch_z = patch_z_begin,
            .lod = lod,
            .patch_type_id = patch_type_id,
        };
    }

    pub fn getLookupsFromRectangle(patch_type_id: PatchTypeId, area: RequestRectangle, lod: LoD, out_lookups: *std.ArrayList(PatchLookup)) void {

        // NOTE(Anders) HACK!
        const patch_lod_end = lod_3_patches_side * std.math.pow(u16, 2, 3 - lod);

        const world_stride = lod_0_patch_size * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(lod)));
        const patch_x_begin_i = @as(i32, @intFromFloat(@divFloor(area.x, world_stride)));
        const patch_z_begin_i = @as(i32, @intFromFloat(@divFloor(area.z, world_stride)));
        const patch_x_end_i = @as(i32, @intFromFloat(@ceil((area.x + area.width) / world_stride)));
        const patch_z_end_i = @as(i32, @intFromFloat(@ceil((area.z + area.height) / world_stride)));
        const patch_x_begin = @as(u16, @intCast(std.math.clamp(patch_x_begin_i, 0, patch_lod_end)));
        const patch_z_begin = @as(u16, @intCast(std.math.clamp(patch_z_begin_i, 0, patch_lod_end)));
        const patch_x_end = @as(u16, @intCast(std.math.clamp(patch_x_end_i, 0, patch_lod_end)));
        const patch_z_end = @as(u16, @intCast(std.math.clamp(patch_z_end_i, 0, patch_lod_end)));

        var patch_z = patch_z_begin;
        while (patch_z < patch_z_end) : (patch_z += 1) {
            var patch_x = patch_x_begin;
            while (patch_x < patch_x_end) : (patch_x += 1) {
                const patch_lookup = PatchLookup{
                    .patch_x = patch_x,
                    .patch_z = patch_z,
                    .lod = lod,
                    .patch_type_id = patch_type_id,
                };
                out_lookups.appendAssumeCapacity(patch_lookup);
            }
        }
    }

    fn updateDependencyPrioritiesRecursively(self: *WorldPatchManager, patch: *Patch, dependency_ctx: PatchTypeContext) void {
        const patch_type = self.patch_types.items[patch.lookup.patch_type_id];
        if (patch_type.dependenciesFn) |dependenciesFn| {
            var dependency_list: [max_dependencies]PatchLookup = undefined;
            const dependency_slice = dependenciesFn(patch.lookup, &dependency_list, dependency_ctx);
            for (dependency_slice) |dependency_lookup| {
                const dependency_patch_handle = self.handle_map_by_lookup.get(dependency_lookup).?;
                const dependency_patch: *Patch = self.patch_pool.getColumnPtrAssumeLive(dependency_patch_handle, .patch);

                // Update the bucket placement even if we are at the same priority. Dependencies need to be loaded first.
                const dependency_is_same_or_lower_prio = !patch.highest_prio.lowerThan(dependency_patch.highest_prio);
                if (dependency_is_same_or_lower_prio) {
                    const prio_old = dependency_patch.highest_prio;
                    dependency_patch.highest_prio = patch.highest_prio;
                    if (dependency_patch.data == null) {
                        // This dependency hasn't been loaded yet
                        self.bucket_queue.updateElems(util.sliceOfInstanceConst(PatchHandle, &dependency_patch_handle), prio_old, dependency_patch.highest_prio);
                        self.updateDependencyPrioritiesRecursively(dependency_patch, dependency_ctx);
                    }
                }
            }
        }
    }

    pub fn addLoadRequestFromLookups(self: *WorldPatchManager, requester_id: RequesterId, lookups: []PatchLookup, prio: Priority) void {
        // // NOTE(Anders) 2 is ultimately quite low, its just to see if we hit it.
        var dependency_list: [max_dependencies]PatchLookup = undefined;

        const dependency_ctx = PatchTypeContext{
            .allocator = self.allocator,
            .asset_mgr = self.asset_mgr,
            .world_patch_mgr = self,
        };

        for (lookups) |patch_lookup| {
            const patch_handle_opt = self.handle_map_by_lookup.get(patch_lookup);
            const patch_type = self.patch_types.items[patch_lookup.patch_type_id];
            if (patch_handle_opt) |patch_handle| {
                // This is a patch that something else has already requested to be loaded.

                const patch: *Patch = self.patch_pool.getColumnPtrAssumeLive(patch_handle, .patch);
                const prio_old = patch.highest_prio;
                patch.addOrUpdateRequester(requester_id, prio);

                if (requester_id == dependency_requester_id and patch.status == .not_loaded) {
                    // A patch indicated this lookup is a dependency for it, and we are already queued.
                    // We need to move ourselves to the top of the bucket, *then* ensure that any of *our*
                    // dependencies are moved top the top too.
                    self.bucket_queue.updateElems(util.sliceOfInstanceConst(PatchHandle, &patch_handle), prio_old, patch.highest_prio);
                    self.updateDependencyPrioritiesRecursively(patch, dependency_ctx);
                } else if (prio_old.lowerThan(patch.highest_prio) and patch.status == .not_loaded) {
                    // We got a new non-dependency request for this patch, update our position in the queue
                    // and the priority of any dependencies.
                    self.bucket_queue.updateElems(util.sliceOfInstanceConst(PatchHandle, &patch_handle), prio_old, patch.highest_prio);
                    self.updateDependencyPrioritiesRecursively(patch, dependency_ctx);
                }

                continue;
            }

            const world_stride = lod_0_patch_size * std.math.pow(u32, 2, patch_lookup.lod);
            var patch = Patch{
                .lookup = patch_lookup,
                .patch_x = patch_lookup.patch_x,
                .patch_z = patch_lookup.patch_z,
                .world_x = patch_lookup.patch_x * world_stride,
                .world_z = patch_lookup.patch_z * world_stride,
                .patch_type_id = patch_lookup.patch_type_id,
            };
            patch.addOrUpdateRequester(requester_id, prio);

            if (DEBUG_LOGGING) std.log.debug("WPM: Pushing {}, Pr{} to queue", .{ patch.lookup, @intFromEnum(patch.highest_prio) });

            // NOTE(Anders): Since the bucket queue is LIFO, it's important that we add this patch first
            // before any potential dependencies, so that they are loaded first.
            const patch_handle = self.patch_pool.add(.{ .patch = patch }) catch unreachable;
            self.handle_map_by_lookup.put(patch_lookup, patch_handle) catch unreachable;
            self.bucket_queue.pushElems(util.sliceOfInstanceConst(PatchHandle, &patch_handle), prio);

            if (patch_type.dependenciesFn) |dependenciesFn| {
                const dependency_slice = dependenciesFn(patch_lookup, &dependency_list, dependency_ctx);
                self.addLoadRequestFromLookups(0, dependency_slice, prio);
            }
        }
    }

    pub fn removeLoadRequestFromLookups(self: *WorldPatchManager, requester_id: RequesterId, lookups: []PatchLookup) void {
        for (lookups) |patch_lookup| {
            const patch_handle_opt = self.handle_map_by_lookup.get(patch_lookup);
            if (patch_handle_opt) |patch_handle| {
                const patch: *Patch = self.patch_pool.getColumnPtrAssumeLive(patch_handle, .patch);
                const prio_old = patch.highest_prio;
                patch.removeRequester(requester_id);
                if (!patch.hasRequests()) {
                    self.unloadPatch(patch_handle, patch);
                    continue;
                }

                if (patch.highest_prio != prio_old and patch.status == .not_loaded) {
                    self.bucket_queue.updateElems(util.sliceOfInstanceConst(PatchHandle, &patch_handle), prio_old, patch.highest_prio);
                }
            }
        }
    }

    pub fn tryGetPatch(self: WorldPatchManager, patch_lookup: PatchLookup, comptime T: type) struct { status: PatchStatus, data_opt: ?*T } {
        const patch_handle_opt = self.handle_map_by_lookup.get(patch_lookup);
        if (patch_handle_opt) |patch_handle| {
            const patch: *Patch = self.patch_pool.getColumnPtrAssumeLive(patch_handle, .patch);
            if (patch.data) |data| {
                const data_aligned: []align(@alignOf(*T)) u8 = @alignCast(data);
                const value = std.mem.bytesAsValue(T, data_aligned);
                // const data_aligned : align(@alignOf(T)) []u8 = @alignCast(data);
                return .{
                    .status = patch.status,
                    .data_opt = value,
                };
            }
            return .{ .status = patch.status, .data_opt = null };
        }

        return .{ .status = .nonexistent, .data_opt = null };
    }

    pub fn tickAll(self: *WorldPatchManager) void {
        while (self.bucket_queue.peek()) {
            self.tickOne();
        }
    }

    pub fn tickOne(self: *WorldPatchManager) void {
        var patch_handle: PatchHandle = PatchHandle.nil;
        if (self.bucket_queue.popElems(util.sliceOfInstance(PatchHandle, &patch_handle)) > 0) {
            var patch = self.patch_pool.getColumnPtrAssumeLive(patch_handle, .patch);
            const patch_type = self.patch_types.items[patch.patch_type_id];
            const ctx = PatchTypeContext{
                .allocator = self.allocator,
                .asset_mgr = self.asset_mgr,
                .world_patch_mgr = self,
            };
            if (DEBUG_LOGGING) std.log.debug("WPM: Loading {}, Pr{}", .{ patch.lookup, @intFromEnum(patch.highest_prio) });
            patch_type.loadFn(patch, ctx);
            if (patch.data != null) {
                patch.status = .loaded;
            }
            std.debug.assert(patch.status != .not_loaded);

            // Unload any dependency patches
            if (patch_type.dependenciesFn) |dependenciesFn| {
                const dependency_ctx = PatchTypeContext{
                    .allocator = self.allocator,
                    .asset_mgr = self.asset_mgr,
                    .world_patch_mgr = self,
                };

                var dependency_list: [max_dependencies]PatchLookup = undefined;
                const dependency_slice = dependenciesFn(patch.lookup, &dependency_list, dependency_ctx);
                for (dependency_slice) |dependency_lookup| {
                    const dependency_patch_handle = self.handle_map_by_lookup.get(dependency_lookup).?;
                    const dependency_patch: *Patch = self.patch_pool.getColumnPtrAssumeLive(dependency_patch_handle, .patch);
                    dependency_patch.removeRequester(dependency_requester_id);
                    if (!dependency_patch.hasRequests()) {
                        if (DEBUG_LOGGING) std.log.debug("WPM: Unloading {} dependent={}", .{ dependency_patch.lookup, patch.lookup });
                        self.unloadPatch(dependency_patch_handle, dependency_patch);
                    }
                }
            }
        }
    }

    fn unloadPatch(self: *WorldPatchManager, patch_handle: PatchHandle, patch: *Patch) void {
        if (DEBUG_LOGGING) std.log.debug("WPM: Unloading {}", .{patch.lookup});
        if (patch.data != null) {
            self.allocator.free(patch.data.?);
            patch.data = null;
        } else {
            if (patch.status == .not_loaded) {
                self.bucket_queue.removeElems(util.sliceOfInstanceConst(PatchHandle, &patch_handle));
            }

            // Unload any dependency patches
            const patch_type = self.patch_types.items[patch.patch_type_id];
            if (patch_type.dependenciesFn) |dependenciesFn| {
                const dependency_ctx = PatchTypeContext{
                    .allocator = self.allocator,
                    .asset_mgr = self.asset_mgr,
                    .world_patch_mgr = self,
                };

                var dependency_list: [max_dependencies]PatchLookup = undefined;
                const dependency_slice = dependenciesFn(patch.lookup, &dependency_list, dependency_ctx);
                for (dependency_slice) |dependency_lookup| {
                    const dependency_patch_handle = self.handle_map_by_lookup.get(dependency_lookup).?;
                    const dependency_patch: *Patch = self.patch_pool.getColumnPtrAssumeLive(dependency_patch_handle, .patch);
                    dependency_patch.removeRequester(dependency_requester_id);
                    if (!dependency_patch.hasRequests()) {
                        self.unloadPatch(dependency_patch_handle, dependency_patch);
                    }
                }
            }
        }

        self.patch_pool.removeAssumeLive(patch_handle);
        _ = self.handle_map_by_lookup.remove(patch.lookup);
    }
};
