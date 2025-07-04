const std = @import("std");
const g = @import("../game_pkg.zig");
const d = @import("dungeon_pkg.zig");
const p = g.primitives;
const u = g.utils;

const log = std.log.scoped(.cave);

pub const rows = 2 * g.DISPLAY_ROWS;
pub const cols = 2 * g.DISPLAY_COLS;
/// The minimal percent of the opened cells
const min_area: usize = @divTrunc(rows * cols * 4, 10);

const Self = @This();

alloc: std.mem.Allocator,
cellural_automata: d.CelluralAutomata,
// The room of this cave with rocks inside
room: d.Room,
/// The bit mask of the places with floor and walls.
cells: u.BitMap(rows, cols),
entrance: ?p.Point = null,
exit: ?p.Point = null,

/// Uses arena to create a self instance and trying to generate a dungeon with passed seed.
pub fn generateDungeon(arena: *std.heap.ArenaAllocator, cellural_automata: d.CelluralAutomata, seed: u64) !?d.Dungeon {
    const alloc = arena.allocator();
    const self = try alloc.create(Self);
    self.* = try init(alloc, cellural_automata);
    return try self.dungeon(seed);
}

pub fn init(alloc: std.mem.Allocator, cellural_automata: d.CelluralAutomata) !Self {
    return .{
        .alloc = alloc,
        .cellural_automata = cellural_automata,
        .room = d.Room.init(p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols }),
        .cells = try u.BitMap(rows, cols).initFull(alloc),
    };
}

pub fn dungeon(self: *Self, seed: u64) !?d.Dungeon {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var tmp_arena = std.heap.ArenaAllocator.init(self.alloc);
    defer tmp_arena.deinit();
    const tmp_alloc = tmp_arena.allocator();

    const prototype_map = try self.cellural_automata.generate(rows, cols, &tmp_arena, seed);
    const tuple = try biggestOpenArea(tmp_alloc, prototype_map);
    log.debug("Generated cave with max open area {d}. Expected > {d}", .{ tuple[0], min_area });
    if (tuple[0] > min_area) {
        log.debug("The cave is successfully generate with seed {d}", .{seed});
        var stack: std.ArrayListUnmanaged(p.Point) = .empty;
        defer stack.deinit(tmp_alloc);

        try stack.append(self.alloc, tuple[1]);
        while (stack.pop()) |point| {
            if (prototype_map.isSet(point.row, point.col)) continue;
            prototype_map.setAt(point);
            self.cells.unsetAt(point);
            try stack.append(tmp_alloc, point.movedTo(.up));
            try stack.append(tmp_alloc, point.movedTo(.down));
            try stack.append(tmp_alloc, point.movedTo(.left));
            try stack.append(tmp_alloc, point.movedTo(.right));
        }
        // TODO move this place far away of each other
        self.entrance = self.randomEmptyPlace(rand);
        self.exit = self.randomEmptyPlace(rand);
        return .{
            .seed = seed,
            .type = .cave,
            .parent = self,
            .rows = rows,
            .cols = cols,
            .entrance = self.entrance.?,
            .exit = self.exit.?,
            .vtable = .{
                .cellAtFn = cellAt,
                .placementWithFn = placementWith,
                .randomPlaceFn = randomPlace,
            },
        };
    }
    return null;
}

/// Returns a maximum number of the opened cells and some point inside them.
fn biggestOpenArea(
    tmp_arena_alloc: std.mem.Allocator,
    map: *const u.BitMap(rows, cols),
) !struct { usize, p.Point } {
    var max_area: usize = 0;
    var max_area_point: p.Point = undefined;
    for (0..rows) |i| {
        for (0..cols) |j| {
            const r: u8 = @intCast(i + 1);
            const c: u8 = @intCast(j + 1);
            if (map.isSet(r, c)) continue;
            const area = try calculateArea(tmp_arena_alloc, map, .{ .row = r, .col = c });
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
    original_map: *const u.BitMap(rows, cols),
    init_point: p.Point,
) !usize {
    var map = try u.BitMap(rows, cols).initEmpty(alloc);
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

fn cellAt(ptr: *const anyopaque, place: p.Point) d.Dungeon.Cell {
    const self: *const Self = @ptrCast(@alignCast(ptr));

    if (!self.room.region.containsPoint(place)) return .nothing;

    return if (self.cells.isSet(place.row, place.col)) .rock else .floor;
}

fn placementWith(ptr: *anyopaque, place: p.Point) ?d.Placement {
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (!self.room.region.containsPoint(place)) return null;

    return .{ .room = &self.room };
}

fn randomPlace(ptr: *const anyopaque, rand: std.Random) p.Point {
    const self: *const Self = @ptrCast(@alignCast(ptr));
    return self.randomEmptyPlace(rand);
}

pub fn randomEmptyPlace(self: *const Self, rand: std.Random) p.Point {
    while (true) {
        const row = self.room.region.top_left.row + rand.uintLessThan(u8, self.room.region.rows - 2) + 1;
        const col = self.room.region.top_left.col + rand.uintLessThan(u8, self.room.region.cols - 2) + 1;
        if (!self.cells.isSet(row, col)) return .{ .row = row, .col = col };
    }
}

test "For same seed should return same dungeon" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buf_expected: [4096]u8 = undefined;
    var buf_actual: [4096]u8 = undefined;

    const seed, var previous = try generateAndWriteDungeon(&arena, &buf_expected, null);

    for (0..10) |_| {
        const used_seed, const current = try generateAndWriteDungeon(&arena, &buf_actual, seed);

        try std.testing.expectEqual(seed, used_seed);
        try std.testing.expectEqualStrings(previous, current);

        previous = current;
    }
}

fn generateAndWriteDungeon(arena: *std.heap.ArenaAllocator, buf: []u8, seed: ?u64) !struct { u64, []const u8 } {
    var rnd = std.Random.DefaultPrng.init(100500);
    var bfw = std.io.fixedBufferStream(buf);
    while (true) {
        const s: u64 = seed orelse rnd.next();
        if (try Self.generateDungeon(arena, .{}, s)) |dunge| {
            const len = try dunge.write(bfw.writer());
            return .{ dunge.seed, buf[0..len] };
        }
    }
}
