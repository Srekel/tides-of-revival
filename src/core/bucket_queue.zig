const std = @import("std");
const expect = std.testing.expect;

pub fn BucketQueue(comptime QueueElement: type, comptime BucketEnum: type) type {
    return struct {
        const Self = @This();
        const Bucket = std.ArrayList(QueueElement);
        const bucket_count: u32 = @typeInfo(BucketEnum).Enum.fields.len;
        const lowest_prio: u32 = bucket_count - 1;

        allocator: std.mem.Allocator,
        buckets: [bucket_count]Bucket = undefined,
        current_highest_prio: u32 = lowest_prio,

        pub fn create(allocator: std.mem.Allocator, bucket_sizes: [bucket_count]u32) Self {
            var result = Self{
                .allocator = allocator,
            };
            for (&result.buckets, 0..) |*bucket, i| {
                bucket.* = Bucket.init(allocator);
                bucket.*.ensureTotalCapacity(bucket_sizes[i]) catch unreachable;
            }
            return result;
        }

        pub fn destroy(self: *Self) void {
            for (self.buckets) |*bucket| {
                bucket.deinit();
            }
        }

        pub fn peek(self: Self) bool {
            if (self.buckets[self.current_highest_prio].items.len == 0) {
                return false;
            }
            return true;
        }

        pub fn pushElems(self: *Self, elems: []const QueueElement, prio: BucketEnum) void {
            const prio_index = @enumToInt(prio);
            self.buckets[prio_index].appendSliceAssumeCapacity(elems);
            if (prio_index < self.current_highest_prio) {
                self.current_highest_prio = prio_index;
            }
        }

        pub fn pushElemsToBottomOfBucket(self: *Self, elems: []const QueueElement, prio: BucketEnum) void {
            const prio_index = @enumToInt(prio);
            self.buckets[prio_index].insertSlice(0, elems) catch unreachable;
            if (prio_index < self.current_highest_prio) {
                self.current_highest_prio = prio_index;
            }
        }

        pub fn popElems(self: *Self, elems_out: []QueueElement) u32 {
            if (self.buckets[self.current_highest_prio].items.len == 0) {
                return 0;
            }

            // TODO: Possibly inverting the two loops may be smarter (faster)
            var count: u32 = 0;
            var bucket_index = self.current_highest_prio;
            for (elems_out) |*elem| {
                var bucket = &self.buckets[bucket_index];
                elem.* = bucket.pop();
                count += 1;
                while (bucket.items.len == 0) {
                    if (bucket_index == lowest_prio) {
                        // No more elements in the queue
                        return count;
                    }
                    bucket_index += 1;
                    bucket = &self.buckets[bucket_index];
                    self.current_highest_prio = bucket_index;
                }
            }
            return count;
        }

        pub fn removeElems(self: *Self, elems: []const QueueElement) void {
            elem_loop: for (elems) |elem| {
                for (&self.buckets, 0..) |*bucket, prio| {
                    for (bucket.items, 0..) |bucket_elem, i| {
                        if (std.meta.eql(bucket_elem, elem)) {
                            _ = bucket.orderedRemove(i);

                            if (prio == self.current_highest_prio) {
                                while (self.buckets[self.current_highest_prio].items.len == 0) {
                                    if (self.current_highest_prio == lowest_prio) {
                                        continue :elem_loop;
                                    }
                                    self.current_highest_prio += 1;
                                }
                            }

                            continue :elem_loop;
                        }
                    }
                }

                unreachable;
            }
        }

        pub fn updateElems(self: *Self, elems: []const QueueElement, prio_old: BucketEnum, prio_new: BucketEnum) void {
            const prio_index_old = @enumToInt(prio_old);
            const prio_index_new = @enumToInt(prio_new);
            var bucket_old = &self.buckets[prio_index_old];
            var bucket_new = &self.buckets[prio_index_new];
            for (elems) |elem| {
                const bucket_old_elem_index = blk: {
                    for (bucket_old.items, 0..) |bucket_old_elem, i| {
                        if (std.meta.eql(elem, bucket_old_elem)) {
                            break :blk i;
                        }
                    }
                    unreachable;
                };
                _ = bucket_old.orderedRemove(bucket_old_elem_index);
                bucket_new.appendAssumeCapacity(elem);
            }

            if (prio_index_new < self.current_highest_prio) {
                self.current_highest_prio = prio_index_new;
            }
        }
    };
}

test "priority_bucket_queue" {
    const MyPrio = enum {
        high,
        med,
        low,
    };
    const MyHandle = u32;
    const MyQueue = BucketQueue(MyHandle, MyPrio);
    var queue = MyQueue.create(std.testing.allocator, [_]u32{ 8, 16, 8 });
    defer queue.destroy();
    var ids_high = [_]MyHandle{ 100, 200, 300 };
    queue.pushElems(ids_high[0..3], .high);
    var ids_med = [_]MyHandle{ 40, 50, 60 };
    queue.pushElems(ids_med[0..3], .med);

    var out_ids = [_]MyHandle{ 0, 0 };
    var popped = queue.popElems(out_ids[0..]);
    std.debug.print("{any}\n", .{out_ids});
    try expect(popped == 2);
    try expect(out_ids[0] == 300);
    try expect(out_ids[1] == 200);

    popped = queue.popElems(out_ids[0..]);
    std.debug.print("{any}\n", .{out_ids});
    try expect(popped == 2);
    try expect(out_ids[0] == 100);
    try expect(out_ids[1] == 60);

    popped = queue.popElems(out_ids[0..]);
    std.debug.print("{any}\n", .{out_ids});
    try expect(popped == 2);

    popped = queue.popElems(out_ids[0..]);
    std.debug.print("{any}\n", .{out_ids});
    try expect(popped == 0);

    // var ids_highlol = [_]MyHandle{ 50, 40 };
    // try expect(out_ids[0..2] == ids_highlol[0..2]);
}
