const std = @import("std");
const IdLocal = @import("../core/core.zig").IdLocal;

pub const TagHash = u64;

const TagData = struct {
    id: IdLocal,
    parents: std.BoundedArray(TagHash, 8),
    children: std.BoundedArray(TagHash, 32), // way too low - should be in the thousands
};

pub const Tags = struct {
    tags: std.ArrayList(TagHash),
    data: TagData,
};

pub const TagsBuilder = struct {
    const TagsBuilderData = struct {
        // hash: TagHash,
        id: IdLocal,
        parents: std.BoundedArray(TagHash, 8),
        children: std.BoundedArray(TagHash, 32), // way too low - should be in the thousands
        island: usize,
        max_depth: u8,
    };

    tags: std.ArrayList(TagsBuilderData),

    pub fn addTagFromId(self: *TagsBuilder, id: IdLocal, parents: []const TagHash) void {
        var td: TagsBuilderData = .{
            .id = id,
            .parents = std.BoundedArray(TagHash, 8).fromSlice(parents),
            .children = .{},
            .max_depth = 0,
        };

        for (parents) |p| {
            if (self.get(p)) |parent_data| {
                td.max_depth = std.math.max(td.max_depth, parent_data.max_depth + 1);
                parent_data.children.append(td.hash);
            }
        }

        for (self.tags) |*td2| {
            for (td2.parents.slice()) |parent_hash| {
                if (td.id.hash == parent_hash) {
                    td2.parents.append(td.hash);
                    td2.max_depth = std.math.max(td2.max_depth, td.max_depth + 1);
                }
            }
        }

        self.tags.append(td);
    }

    fn get(self: *TagsBuilder, tag_hash: TagHash) ?*TagsBuilderData {
        for (self.tags) |*td| {
            if (td.id.hash == tag_hash) {
                return td;
            }
        }

        return null;
    }

    fn assignIsland(self: *TagsBuilder, td: *TagsBuilderData, island: usize) void {
        if (td.island == island) {
            return;
        }
        td.island = island;

        for (td.parents.slice()) |parent_hash| {
            const tdp = self.get(parent_hash).?;
            self.assignIsland(tdp, island);
        }
        for (td.children.slice()) |child_hash| {
            const tdc = self.get(child_hash).?;
            self.assignIsland(tdc, island);
        }
    }

    fn sort(context: void, a: TagsBuilderData, b: TagsBuilderData) bool {
        _ = context; // autofix

        // Place tagdatas in order of islands
        if (a.island < b.island) {
            return true;
        }
        if (a.island > b.island) {
            return false;
        }

        // Place tagdatas in order of depth, i.e.
        if (a.max_depth < b.max_depth) {
            return true;
        }
        if (a.max_depth > b.max_depth) {
            return false;
        }

    return std.sort.asc(u8)
    }

    pub fn build(self: *TagsBuilder) Tags {
        for (self.tags, 1..) |*td, island| {
            if (td.island == 0) {
                self.assignIsland(td, island);
            }
        }

        var tags: Tags = .{};
        _ = tags; // autofix

    }
};
