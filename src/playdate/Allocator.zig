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
            .remap = std.mem.Allocator.noRemap,
        },
    };
}

fn alloc(self_opaq: *anyopaque, len: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
    const playdate: *api.PlaydateAPI = @ptrCast(@alignCast(self_opaq));
    return @as(?[*]u8, @ptrCast(playdate.system.realloc(null, len)));
}

fn resize(_: *anyopaque, buf: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
    return new_len <= buf.len;
}

fn free(self_opaq: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
    const playdate: *api.PlaydateAPI = @ptrCast(@alignCast(self_opaq));
    _ = playdate.system.realloc(buf.ptr, 0);
}
