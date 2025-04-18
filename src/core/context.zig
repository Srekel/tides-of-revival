const std = @import("std");
const v = @import("../core/core.zig").variant;
const IdLocal = @import("../core/core.zig").IdLocal;
const Variant = v.Variant;

pub const Context = struct {
    map: std.AutoHashMap(u64, v.Variant),

    pub fn init(allocator: std.mem.Allocator) Context {
        _ = allocator;
        const res = Context{
            .map = std.AutoHashMap(u64, v.Variant).init(std.heap.page_allocator),
        };
        return res;
    }

    pub fn put(self: *Context, id: IdLocal, ptr: anytype) void {
        const variant = Variant.createPtr(ptr, 1);
        self.map.put(id.hash, variant) catch unreachable;
    }

    pub fn putOpaque(self: *Context, id: IdLocal, ptr: anytype) void {
        const variant = Variant.createPtrOpaque(ptr, 1);
        self.map.put(id.hash, variant) catch unreachable;
    }

    pub fn putConst(self: *Context, id: IdLocal, ptr: anytype) void {
        const variant = Variant.createPtrConst(ptr, 1);
        self.map.put(id.hash, variant) catch unreachable;
    }

    pub fn get(self: Context, id: u64, comptime T: type) *T {
        const variant = self.map.get(id).?;
        const ptr = variant.getPtr(T, 1);
        return ptr;
    }

    pub fn getConst(self: Context, id: u64, comptime T: type) *const T {
        var variant = self.map.get(id).?;
        const ptr = variant.getPtrConst(T, 1);
        return ptr;
    }
};

pub fn CONTEXTIFY(comptime InnerContextT: type) type {
    return struct {
        pub fn view(outerContext: anytype) InnerContextT {
            var innerContext: InnerContextT = undefined;
            inline for (std.meta.fields(InnerContextT)) |fld| {
                if (comptime !std.mem.startsWith(u8, fld.name, @as([:0]const u8, "state"))) {
                    @field(innerContext, fld.name) = @field(outerContext, fld.name);
                }
            }
            return innerContext;
        }
    };
}
