const std = @import("std");
const g = @import("../game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;
const CelluralAutomata = @import("CelluralAutomata.zig");

const log = std.log.scoped(.caves_generator);

pub fn CavesGenerator(comptime rows: comptime_int, comptime cols: comptime_int) type {
    return struct {
        const Self = @This();

        cellural_automata: CelluralAutomata = .{},

        pub fn generateDungeon(
            self: Self,
            arena: *std.heap.ArenaAllocator,
            rand: std.Random,
        ) !d.Dungeon {
            const alloc = arena.allocator();

            const generate_arena = try alloc.create(std.heap.ArenaAllocator);
            defer alloc.destroy(generate_arena);

            generate_arena.* = std.heap.ArenaAllocator.init(alloc);
            defer generate_arena.deinit();

            const dungeon = try arena.allocator().create(d.Cave(rows, cols));
            dungeon.* = try d.Cave(rows, cols).init(arena);
            dungeon.cells.copyFrom(
                try generate(arena.allocator(), rand, self.cellural_automata, 20),
            );
            // TODO move this place far away of each other
            dungeon.entrance = dungeon.randomEmptyPlace(rand);
            dungeon.exit = dungeon.randomEmptyPlace(rand);
            return dungeon.dungeon();
        }

        /// Repeatedly generates caves until one of them will have more than 40% of opened cells.
        /// Generates panic after the `max_attempts`.
        fn generate(
            alloc: std.mem.Allocator,
            rand: std.Random,
            cellural_automata: CelluralAutomata,
            max_attempts: u8,
        ) !*p.BitMap(rows, cols) {
            const min_area: usize = @divTrunc(rows * cols * 4, 10);
            for (0..max_attempts) |attempt| {
                var tmp_arena = std.heap.ArenaAllocator.init(alloc);
                defer tmp_arena.deinit();

                const prototype_map = try cellural_automata.generate(rows, cols, &tmp_arena, rand);
                const tuple = try biggestOpenArea(alloc, prototype_map);
                log.debug("Generated cave with max open area {d}. Expected > {d}", .{ tuple[0], min_area });
                // now, let's create the final result and clear the biggest area
                if (tuple[0] > min_area) {
                    const result = try alloc.create(p.BitMap(rows, cols));
                    result.* = try p.BitMap(rows, cols).initFull(alloc);
                    var stack = std.ArrayList(p.Point).init(alloc);
                    defer stack.deinit();
                    try stack.append(tuple[1]);
                    while (stack.popOrNull()) |point| {
                        if (prototype_map.isSet(point.row, point.col)) continue;
                        prototype_map.setAt(point);
                        result.unsetAt(point);
                        try stack.append(point.movedTo(.up));
                        try stack.append(point.movedTo(.down));
                        try stack.append(point.movedTo(.left));
                        try stack.append(point.movedTo(.right));
                    }
                    log.debug("The cave was generate on {d} attempt", .{attempt + 1});
                    return result;
                }
            }
            std.debug.panic("No one cave was generated after {d} attempts", .{max_attempts});
        }

        fn biggestOpenArea(
            alloc: std.mem.Allocator,
            map: *const p.BitMap(rows, cols),
        ) !struct { usize, p.Point } {
            var max_area: usize = 0;
            var max_area_point: p.Point = undefined;
            for (0..rows) |i| {
                for (0..cols) |j| {
                    const r: u8 = @intCast(i + 1);
                    const c: u8 = @intCast(j + 1);
                    if (map.isSet(r, c)) continue;
                    const area = try calculateArea(alloc, map, .{ .row = r, .col = c });
                    if (area > max_area) {
                        max_area = area;
                        max_area_point.row = r;
                        max_area_point.col = c;
                    }
                }
            }
            return .{ max_area, max_area_point };
        }

        fn calculateArea(
            alloc: std.mem.Allocator,
            original_map: *const p.BitMap(rows, cols),
            init_point: p.Point,
        ) !usize {
            var map = try p.BitMap(rows, cols).initEmpty(alloc);
            defer map.deinit();
            map.copyFrom(original_map);

            var area: usize = 0;

            var stack = std.ArrayList(p.Point).init(alloc);
            defer stack.deinit();
            try stack.append(init_point);

            while (stack.popOrNull()) |point| {
                if (map.isSet(point.row, point.col)) continue;
                area += 1;
                map.set(point.row, point.col);
                try stack.append(point.movedTo(.up));
                try stack.append(point.movedTo(.down));
                try stack.append(point.movedTo(.left));
                try stack.append(point.movedTo(.right));
            }
            return area;
        }
    };
}
