const std = @import("std");
const IdLocal = @import("../core/core.zig").IdLocal;

pub const TagHash = u64;
const TagIndex = u16;

const TagData = struct {
    id: IdLocal,

    // Note: Could switch these out for a continuous array in Tags for less memory.
    parents: std.BoundedArray(TagIndex, 4),
    children: std.BoundedArray(TagIndex, 32),
};

pub const Tags = struct {
    tags: std.ArrayList(TagHash),
    tag_lookup: std.AutoHashMap(TagHash, u16),
    data: TagData,

    pub fn getIndex(self: Tags, hash: TagHash) TagIndex {
        const td_index = self.tag_lookup.get(hash).?;
        return td_index;
    }

    pub fn isA(self: Tags, index: TagIndex, parent_hash: TagHash) bool {
        const td = self.data[index];
        for (td.parents.slice()) |parent_index| {
            if (self.tags[parent_index] == parent_hash) {
                return true;
            }

            if (self.isA(parent_index, parent_hash)) {
                return true;
            }
        }

        return false;
    }

    pub fn isA_fromHash(self: Tags, hash: TagHash, parent_hash: TagHash) bool {
        const td_index = self.getIndex(hash);
        return self.isA(td_index, parent_hash);
    }
};

pub const TagsBuilder = struct {
    const TagsBuilderData = struct {
        // hash: TagHash,
        id: IdLocal,
        parents: std.BoundedArray(TagHash, 8),
        children: std.BoundedArray(TagHash, 32),
        island: usize,
        depth: u8,
    };

    tags: std.ArrayList(TagsBuilderData),

    pub fn addTagFromId(self: *TagsBuilder, id: IdLocal, parents: []const TagHash) void {
        var td: TagsBuilderData = .{
            .id = id,
            .parents = std.BoundedArray(TagHash, 8).fromSlice(parents),
            .children = .{},
            .depth = 0,
        };

        for (parents) |p| {
            if (self.get(p)) |parent_data| {
                td.depth = std.math.max(td.depth, parent_data.depth + 1);
                parent_data.children.append(td.hash);
            }
        }

        for (self.tags) |*td2| {
            for (td2.parents.slice()) |parent_hash| {
                if (td.id.hash == parent_hash) {
                    td2.parents.append(td.hash);
                    td2.depth = std.math.max(td2.depth, td.max_depth + 1);
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

        // Place tagdatas in order of depth, i.e. roots first, then parents, children last.
        if (a.max_depth < b.depth) {
            return true;
        }
        if (a.depth > b.depth) {
            return false;
        }

        // Finally just sort by name (for convenience - for uniqueness the hash would be sufficient)
        switch (std.ascii.orderIgnoreCase(a.id.toString(), b.id.toString())) {
            .eq => unreachable,
            .gt => return true,
            .lt => return false,
        }
    }

    pub fn build(self: *TagsBuilder) Tags {
        for (self.tags, 1..) |*td, island| {
            if (td.island == 0) {
                self.assignIsland(td, island);
            }
        }

        std.mem.sort(TagsBuilderData, self.tags, void, self.sort);
        var tags: Tags = .{};

        for (self.tags) |tbd| {
            tags.tags.append(tbd.id.hash);

            var td: TagData = .{
                .id = tbd.id,
                .parents = .{},
                .children = .{},
            };

            for (tbd.parents.slice()) |parent_hash| {
                const tbdp = self.get(parent_hash).?;
                const parent_index = tbdp - self.tags.items.ptr;
                const index: TagIndex = @intCast(parent_index);
                td.parents.append(index);
            }

            for (tbd.children.slice()) |child_hash| {
                const tbdc = self.get(child_hash).?;
                const parent_index = tbdc - self.tags.items.ptr;
                const index: TagIndex = @intCast(parent_index);
                td.children.append(index);
            }

            tags.data.append(td);
        }

        return tags;
    }
};

pub fn buildFromJson (json:std.json.)