const std = @import("std");
const window = @import("window.zig");
const zglfw = @import("zglfw");
const zphy = @import("zphysics");
const zm = @import("zmath");
const zmesh = @import("zmesh");

// pub const GameContext = struct {
//     constvars: std.AutoHashMap(IdLocal, []const u8),
//     vars: std.AutoHashMap(IdLocal, []u8),
//     fn getConst(self: GameContext, comptime T: type, id: IdLocal) *const T {

//     }
// };

const IdLocal = @import("variant.zig").IdLocal;
const fd = @import("flecs_data.zig");
const flecs = @import("flecs");

// pub fn giveTransform(ent: flecs.Entity, pos: ?fd.Position, rot: ?fd.EulerRotation) void {
//     ent.setPair(fd.Position, fd.LocalSpace, pos);
//     ent.addPair(fd.Position, fd.WorldSpace);
//     ent.set(fd.EulerRotation{});
//     ent.set(fd.Scale{});
//     ent.set(fd.Transform{});
//     ent.set(fd.Forward{});
// }
