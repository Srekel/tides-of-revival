const std = @import("std");
const IdLocal = @import("../core/core.zig").IdLocal;

pub const EventCallback = *const fn (ctx: *anyopaque, event_id: u64, event_data: *const anyopaque) void;

pub const EventListener = struct {
    // event_id: IdLocal,
    ctx: *anyopaque,
    func: EventCallback,
};

pub const EventManager = struct {
    allocator: std.mem.Allocator,
    event_map: std.AutoHashMap(u64, std.ArrayList(EventListener)),

    pub fn create(allocator: std.mem.Allocator) EventManager {
        var event_map = std.AutoHashMap(u64, std.ArrayList(EventListener)).init(allocator);
        event_map.ensureTotalCapacity(1024) catch unreachable;
        return .{
            .allocator = allocator,
            .event_map = event_map,
        };
    }

    pub fn destroy(self: *EventManager) void {
        self.event_map.deinit();
    }

    pub fn registerListener(self: *EventManager, event_id: IdLocal, callback: EventCallback, ctx: anytype) void {
        if (!self.event_map.contains(event_id.hash)) {
            const listeners = std.ArrayList(EventListener).initCapacity(self.allocator, 16) catch unreachable;
            self.event_map.putAssumeCapacity(event_id.hash, listeners);
        }
        var listeners = self.event_map.getPtr(event_id.hash).?;
        listeners.appendAssumeCapacity(.{ .ctx = ctx, .func = callback });
    }

    pub fn triggerEvent(self: EventManager, event_id: IdLocal, event_data: *const anyopaque) void {
        if (self.event_map.get(event_id.hash)) |listeners| {
            // const listeners = &;
            for (listeners.items) |listener| {
                listener.func(listener.ctx, event_id.hash, event_data);
            }
        }
    }
};
