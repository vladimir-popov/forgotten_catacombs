const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;

/// The rows and columns include the borders
pub fn Window(comptime rows: u8, cols: u8) type {
    return struct {
        const Self = @This();

        const Line = [cols - 3]u8;

        arena: *std.heap.ArenaAllocator,
        /// The scrollable content of the window, EXCEPT the border and one line for scroll.
        lines: std.ArrayList(Line),
        scroll: u8,

        pub fn create(alloc: std.mem.Allocator) !*Self {
            std.log.debug("Create a window", .{});
            const arena = try alloc.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(alloc);
            const self = try arena.allocator().create(Self);
            self.arena = arena;
            self.scroll = 0;
            self.lines = try std.ArrayList(Line).initCapacity(arena.allocator(), rows - 2);
            std.log.debug("The window was created", .{});
            return self;
        }

        pub fn destroy(self: Self) void {
            const alloc = self.arena.child_allocator;
            self.arena.deinit();
            alloc.destroy(self.arena);
        }

        pub fn addOneLine(self: *Self) !*Line {
            const line = try self.lines.addOne();
            line.* = [1]u8{' '} ** (cols - 3);
            return line;
        }
    };
}
