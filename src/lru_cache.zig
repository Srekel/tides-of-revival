const std = @import("std");
const time = std.time;

pub const LRUKey = u64;
pub const LRUValue = *anyopaque;

pub const LRUCacheEntry = struct {
    key: LRUKey,
    value: LRUValue,
    timestamp: i128,
};

pub const LRUCache = struct {
    allocator: std.mem.Allocator,
    entries: std.MultiArrayList(LRUCacheEntry),
    max_entries: u64,

    pub fn init(self: *LRUCache, allocator: std.mem.Allocator, max_entries: u64) void {
        self.allocator = allocator;
        self.entries = .{};
        self.max_entries = max_entries;
        self.entries.ensureTotalCapacity(allocator, max_entries) catch unreachable; // HACK
    }

    pub fn deinit(self: *LRUCache) void {
        self.entries.deinit(self.allocator);
    }

    pub fn has(self: *LRUCache, key: LRUKey) bool {
        const keys = self.entries.items(.key);
        for (keys) |entry_key| {
            if (entry_key == key) {
                return true;
            }
        }
        return false;
    }

    pub fn try_get(self: *LRUCache, key: LRUKey, evict_key: *?LRUKey, evict_value: *?LRUValue) ?*LRUValue {
        const keys = self.entries.items(.key);
        const values = self.entries.items(.value);
        const timestamps = self.entries.items(.timestamp);

        for (keys) |entry_key, i| {
            if (entry_key == key) {
                timestamps[i] = time.nanoTimestamp();
                return &values[i];
            }
        }

        if (keys.len < self.max_entries) {
            return null;
        }

        var last_timestamp: i128 = std.math.maxInt(i128);
        for (timestamps) |entry_timestamp, i| {
            if (entry_timestamp < last_timestamp) {
                last_timestamp = timestamps[i];
                evict_key.* = keys[i];
                evict_value.* = values[i];
            }
        }

        return null;
    }

    pub fn put(self: *LRUCache, key: LRUKey, value: LRUValue) void {
        std.debug.assert(!self.has(key));
        std.debug.assert(self.entries.len < self.max_entries);
        const entry: LRUCacheEntry = .{
            .key = key,
            .value = value,
            .timestamp = time.nanoTimestamp(),
        };
        self.entries.append(self.allocator, entry) catch unreachable;
    }

    pub fn remove(self: *LRUCache, key: LRUKey) *LRUValue {
        const keys = self.entries.items(.key);
        const values = self.entries.items(.value);
        for (keys) |entry_key, i| {
            if (entry_key == key) {
                const value_ptr = values[i];
                self.entries.swapRemove(i);
                return value_ptr;
            }
        }

        unreachable;
    }

    // pub fn replace(self: *LRUCache, old_entry: LRUCacheEntry, new_key: LRUKey, new_value: LRUValue) void {
    pub fn replace(self: *LRUCache, old_key: LRUKey, new_key: LRUKey, new_value: LRUValue) void {
        std.debug.assert(!self.has(new_key));

        const keys = self.entries.items(.key);
        const values = self.entries.items(.value);
        const timestamps = self.entries.items(.timestamp);

        for (keys) |entry_key, i| {
            if (entry_key == old_key) {
                keys[i] = new_key;
                values[i] = new_value;
                timestamps[i] = time.nanoTimestamp();
                return;
            }
        }

        unreachable;
    }

    pub fn touch(self: *LRUCache, key: LRUKey) void {
        const keys = self.entries.items(.key);
        const timestamps = self.entries.items(.timestamp);
        for (keys) |entry_key, i| {
            if (entry_key == key) {
                timestamps[i] = time.nanoTimestamp();
                return;
            }
        }

        unreachable;
    }
};
