const std = @import("std");
const img = @import("zigimg");
const Pool = @import("zpool").Pool;
const IdLocal = @import("../core/core.zig").IdLocal;
const BucketQueue = @import("../core/bucket_queue.zig").BucketQueue;

pub const Urgency = enum {
    instant_blocking,
    instant_start,
    hard_before_next_frame,
    soft_within_frames,
    soft_within_seconds,
    soft_within_minutes,
};

const Asset = struct {
    status: enum { not_found, exists, loading, loaded },
    data: ?[]u8,
    timestamp: i64,
};

pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    assets: std.AutoHashMap(u64, Asset),

    pub fn create(allocator: std.mem.Allocator) AssetManager {
        var res = AssetManager{
            .allocator = allocator,
            .assets = std.AutoHashMap(u64, Asset).init(allocator),
        };
        res.assets.ensureTotalCapacity(8192) catch unreachable;
        return res;
    }

    pub fn destroy(self: *AssetManager) void {
        self.assets.deinit();
    }

    pub fn doesAssetExist(self: AssetManager, id: IdLocal) bool {
        _ = self;
        std.fs.cwd().access(id.toString(), .{ .mode = .read_only }) catch {
            return false;
        };
        return true;
    }

    pub fn loadAssetBlocking(self: *AssetManager, id: IdLocal, urgency: Urgency) []u8 {
        _ = urgency;
        var asset_opt = self.assets.getPtr(id.hash);
        if (asset_opt) |asset| {
            asset.timestamp = std.time.timestamp();
            if (asset.data) |data| {
                return data;
            }

            const file = std.fs.cwd().openFile(id.toString(), .{ .mode = .read_only }) catch unreachable;
            defer file.close();
            const contents = file.reader().readAllAlloc(self.allocator, 256 * 1024) catch unreachable;
            const contents_snug = self.allocator.alignedAlloc(u8, 32, contents.len) catch unreachable;
            std.mem.copy(u8, contents_snug, contents);
            self.allocator.free(contents);
            asset.data = contents_snug;
            asset.status = .loaded;
            return contents_snug;
        }

        const file = std.fs.cwd().openFile(id.toString(), .{ .mode = .read_only }) catch unreachable;
        defer file.close();
        const contents = file.reader().readAllAlloc(self.allocator, 256 * 1024) catch unreachable;
        const contents_snug = self.allocator.alloc(u8, contents.len) catch unreachable;
        std.mem.copy(u8, contents_snug, contents);
        self.allocator.free(contents);
        var asset = Asset{
            .status = .loaded,
            .data = contents_snug,
            .timestamp = std.time.timestamp(),
        };
        self.assets.putAssumeCapacity(id.hash, asset);
        return contents_snug;
    }
};
