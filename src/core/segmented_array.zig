const std = @import("std");

pub fn SegmentedArray(ElemType: type) type {
    return struct {
        pub const Chunk = struct {
            items: [chunk_size]ElemType = undefined,
            count: u8 = 0,
        };

        const Self = @This();
        const chunk_size = 256;

        allocator: std.mem.Allocator,
        chunk_list: std.ArrayListUnmanaged(*Chunk),
        free_chunks: std.ArrayListUnmanaged(*Chunk),

        pub fn create(allocator: std.mem.Allocator) Self {
            const self = Self{
                .allocator = allocator,
                .chunk_list = .{},
                .free_chunks = .{},
            };
            _ = self; // autofix
        }

        pub fn len(self: Self) usize {
            var size = 0;
            for (self.chunk_list.items) |chunk| {
                size += chunk.count;
            }
            return size;
        }

        pub fn append(self: *Self, item: ElemType) void {
            var last_index = self.chunk_list.items.len - 1;
            const last = self.chunk_list.items[last_index];
            if (last.count == chunk_size) {
                self.chunk_list.append(self.grabFreeChunk());
                last_index += 1;
            }

            const chunk = self.chunk_list.items[last_index];
            chunk.items[chunk.count] = item;
            chunk.count += 1;
        }

        pub fn insertAt(self: *Self, item: ElemType, index: usize) void {
            if (index == self.chunk_list.items.len * chunk_size) {
                self.append(item);
                return;
            }

            const chunk_index = index / chunk_size;
            const chunk = self.chunk_list.items[chunk_index];
            if (chunk.count == chunk_size) {
                // split chunk into two chunks, lc and rc, down middle
                // TODO: memcpy
                const lc = chunk; // left chunk
                const rc = self.grabFreeChunk(); // right chunk
                lc.count = chunk_size / 2;
                rc.count = chunk_size / 2;
                for (chunk_size / 2..chunk_size, 0..chunk_size / 2) |i_lc, i_rc| {
                    rc[i_rc] = lc[i_lc];
                }

                const insert_index = index % chunk_size;
                const insert_chunk = if (insert_index < chunk_size / 2) lc else rc;
                const insert_index_actual = if (insert_index < chunk_size / 2) insert_index else insert_index / 2;
                for (insert_index_actual..chunk_size / 2) |i_c| {
                    insert_chunk[i_c + 1] = insert_chunk[i_c];
                }

                insert_chunk[insert_index_actual] = item;
                insert_chunk.count += 1;
                return;
            }

            chunk.items[chunk.count] = item;
            chunk.count += 1;
        }

        fn grabFreeChunk(self: *Self) *Chunk {
            if (self.free_chunks.items.len == 0) {
                const chunk = self.allocator.create(Chunk) catch unreachable;
                self.free_chunks.append(self.allocator, chunk);
            }
            const chunk = self.free_chunks.pop().?;
            return chunk;
        }
    };
}

const testing = std.testing;

test "return OutOfMemory when capacity would exceed maximum usize integer value" {
    const a = testing.allocator;

    {
        const list = SegmentedArray(f32).create(a);
        try testing.expect(list.len() == 0);
        list.append(1);
        list.append(1);
        try testing.expect(list.len() == 2);
    }
}
