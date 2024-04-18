const std = @import("std");
const cmp = @import("components.zig");

pub fn Player(entity_builder: anytype, init_row: u8, init_col: u8) void {
    entity_builder.addComponent(cmp.Position, .{ .row = init_row, .col = init_col });
    entity_builder.addComponent(cmp.Sprite, .{ .letter = "@" });
}

pub fn Level(entity_builder: anytype, alloc: std.mem.Allocator, rows: u8, cols:u8) !void {
    entity_builder.addComponent(cmp.Level, try cmp.Level.init(alloc, rows, cols));
}
