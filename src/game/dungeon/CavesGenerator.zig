const std = @import("std");
const g = @import("../game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;
const CelluralAutomata = @import("CelluralAutomata.zig");

const log = std.log.scoped(.caves_generator);

pub const rows = 2 * g.DISPLAY_ROWS;
pub const cols = 2 * g.DISPLAY_COLS;

pub fn generateDungeon(
    arena: *std.heap.ArenaAllocator,
    init_seed: u64,
    cellural_automata: CelluralAutomata,
) !d.Dungeon {
    const cave = try arena.allocator().create(d.Cave(rows, cols));
    cave.* = try d.Cave(rows, cols).init(arena);
    const seed = try generate(&cave.cells, arena.allocator(), init_seed, cellural_automata, 20);
    var prng = std.Random.DefaultPrng.init(seed);
    // TODO move this place far away of each other
    cave.entrance = cave.randomEmptyPlace(prng.random());
    cave.exit = cave.randomEmptyPlace(prng.random());
    // the cave it self will be removed on arena deinit
    return cave.dungeon(seed);
}

/// Repeatedly generates cells for a cave until one of them will have more than 40% of opened cells.
/// Generates panic after the `max_attempts`.
fn generate(
    cells: *p.BitMap(rows, cols),
    alloc: std.mem.Allocator,
    init_seed: u64,
    cellural_automata: CelluralAutomata,
    max_attempts: u8,
) !u64 {
    var prng = std.Random.DefaultPrng.init(init_seed);
    const rand = prng.random();
    const min_area: usize = @divTrunc(rows * cols * 4, 10);
    for (0..max_attempts) |attempt| {
        var tmp_arena = std.heap.ArenaAllocator.init(alloc);
        defer tmp_arena.deinit();

        // generate a new seed
        const seed = prng.next();
        prng.seed(seed);

        const prototype_map = try cellural_automata.generate(rows, cols, &tmp_arena, rand);
        const tuple = try biggestOpenArea(alloc, prototype_map);
        log.debug("Generated cave with max open area {d}. Expected > {d}", .{ tuple[0], min_area });
        // now, let's create the final result and clear the biggest area
        if (tuple[0] > min_area) {
            cells.* = try p.BitMap(rows, cols).initFull(alloc);
            var stack = std.ArrayList(p.Point).init(alloc);
            defer stack.deinit();
            try stack.append(tuple[1]);
            while (stack.pop()) |point| {
                if (prototype_map.isSet(point.row, point.col)) continue;
                prototype_map.setAt(point);
                cells.unsetAt(point);
                try stack.append(point.movedTo(.up));
                try stack.append(point.movedTo(.down));
                try stack.append(point.movedTo(.left));
                try stack.append(point.movedTo(.right));
            }
            log.debug("The cells for a cave were generate on {d} attempt", .{attempt + 1});
            return seed;
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
    defer map.deinit(alloc);
    map.copyFrom(original_map);

    var area: usize = 0;

    var stack = std.ArrayList(p.Point).init(alloc);
    defer stack.deinit();
    try stack.append(init_point);

    while (stack.pop()) |point| {
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
