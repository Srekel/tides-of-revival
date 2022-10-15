pub fn cast(ptr: *anyopaque, comptime T: type) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), ptr));
}

pub fn memcpy(dst: *anyopaque, src: *const anyopaque, byte_count: u64) void {
    const src_slice = @ptrCast([*]const u8, src)[0..byte_count];
    const dst_slice = @ptrCast([*]u8, dst)[0..byte_count];
    for (src_slice) |byte, i| {
        dst_slice[i] = byte;
    }
}
