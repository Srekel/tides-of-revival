const std = @import("std");

var rng = std.rand.DefaultPrng.init(0x12345678);

/// allows "namespacing" of the componentHandle. Downside is that it is comptime and each one created has a separate type
/// so it cant be embedded in the World easily. TypeStore(1) and TypeStore(2) would create different handles.
pub fn TypeStore(comptime _: u64) type {
    return struct {
        fn componentHandle(comptime _: type) *u64 {
            return &(struct {
                pub var handle: u64 = std.math.maxInt(u64);
            }.handle);
        }

        pub fn componentId(_: @This(), comptime T: type) u64 {
            var handle = componentHandle(T);
            if (handle.* < std.math.maxInt(u64)) {
                return handle.*;
            }

            // TODO: replace with flecs call
            handle.* = rng.random().int(u64);
            return handle.*;
        }
    };
}