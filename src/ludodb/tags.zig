const std = @import("std");
const IdLocal = @import("../core/core.zig").IdLocal;

pub const TagHash = u64;

pub const Tags = struct {
    tag_list: std.ArrayList(TagHash),

    fn addTagFromId(self: *Tags, id: IdLocal, parents: []const IdLocal) void {
        _ = parents; // autofix
        self.tag_list.append(id.hash);
    }
};
