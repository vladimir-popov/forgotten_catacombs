const std = @import("std");
const c = std.c;
const api = @import("api.zig");

pub fn allocator(playdate: *api.PlaydateAPI) std.mem.Allocator {
    return .{
        .ptr = playdate,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .free = free,
        },
    };
}

fn alloc(
    self_opaq: *anyopaque,
    len: usize,
    log2_ptr_align: u8,
    ret_addr: usize,
) ?[*]u8 {
    _ = ret_addr;
    const playdate: *api.PlaydateAPI = @ptrCast(@alignCast(self_opaq));
    std.debug.assert(log2_ptr_align <= comptime std.math.log2_int(usize, @alignOf(std.c.max_align_t)));
    return @as(?[*]u8, @ptrCast(playdate.system.realloc(null, len)));
}

fn resize(
    _: *anyopaque,
    buf: []u8,
    log2_old_align: u8,
    new_len: usize,
    ret_addr: usize,
) bool {
    _ = log2_old_align;
    _ = ret_addr;
    return new_len <= buf.len;
}

fn free(
    self_opaq: *anyopaque,
    buf: []u8,
    log2_old_align: u8,
    ret_addr: usize,
) void {
    _ = log2_old_align;
    _ = ret_addr;
    const playdate: *api.PlaydateAPI = @ptrCast(@alignCast(self_opaq));
    _ = playdate.system.realloc(buf.ptr, 0);
}
