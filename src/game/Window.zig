const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;

/// The width of the window including the borders and optional scroll.
pub fn Window(width: u8) type {
    return struct {
        const Self = @This();
        /// The max length of the visible content of the window
        /// -2 for borders; -1 for scroll.
        pub const cols = width - 3;
        const Line = [cols]u8;

        arena: *std.heap.ArenaAllocator,
        title: [cols]u8,
        /// The scrollable content of the window
        lines: std.ArrayList(Line),
        scroll: u8,

        pub fn create(alloc: std.mem.Allocator) !*Self {
            std.log.debug("Create a window", .{});
            const arena = try alloc.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(alloc);
            const self = try arena.allocator().create(Self);
            self.arena = arena;
            self.scroll = 0;
            self.title = [1]u8{0} ** cols;
            self.lines = std.ArrayList(Line).init(arena.allocator());
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
            line.* = [1]u8{' '} ** cols;
            return line;
        }
    };
}
