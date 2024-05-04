const std = @import("std");
const cmp = @import("components.zig");

pub inline fn Player(entity_builder: anytype, init_row: u8, init_col: u8) void {
    entity_builder.addComponent(cmp.Position, .{ .row = init_row, .col = init_col });
    entity_builder.addComponent(cmp.Sprite, .{ .letter = "@" });
}

pub inline fn Level(
    entity_builder: anytype,
    alloc: std.mem.Allocator,
    rand: std.Random,
) !void {
    entity_builder.addComponent(cmp.Level, try cmp.Level.init(alloc, rand));
}
