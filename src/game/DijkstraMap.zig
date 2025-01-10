//! This is a limited area with precalculated directions lead to the player.
const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;

const DijkstraMap = @This();

const VectorsMap = std.AutoHashMap(p.Point, struct { p.Direction, u8 });

pub const Obstacles = struct {
    context: *const anyopaque,
    isObstacleFn: *const fn (ptr: *const anyopaque, place: p.Point) bool,

    pub inline fn isObstacle(self: Obstacles, place: p.Point) bool {
        return self.isObstacleFn(self.context, place);
    }
};

region: p.Region,
/// The Dijkstra map that provides an optimal direction to the player, and counts of moves
/// needed to achieve the player in that direction.
/// The weight == 0 means that the place is unreachable and has some obstacle.
vectors: VectorsMap,
obstacles: Obstacles,

pub fn init(alloc: std.mem.Allocator, region: p.Region, obstacles: Obstacles) DijkstraMap {
    return .{ .vectors = VectorsMap.init(alloc), .region = region, .obstacles = obstacles };
}

pub fn deinit(self: *DijkstraMap) void {
    self.vectors.deinit();
}

pub fn calculate(self: *DijkstraMap, target: p.Point) !void {
    var openned = std.ArrayList(struct { p.Point, u8 }).init(self.vectors.allocator);
    defer openned.deinit();
    self.vectors.clearRetainingCapacity();

    try openned.append(.{ target, 0 });
    while (openned.popOrNull()) |tuple| {
        const weight: u8 = tuple[1];
        for (&[_]p.Direction{ .left, .up, .right, .down }) |direction| {
            const neighbor = tuple[0].movedTo(direction);
            if (!self.region.containsPoint(neighbor) or neighbor.eql(target) or self.obstacles.isObstacle(neighbor))
                continue;

            const gop = try self.vectors.getOrPut(neighbor);
            if (!gop.found_existing or gop.value_ptr[1] > weight + 1) {
                gop.value_ptr.* = .{ direction.opposite(), weight + 1 };
                try openned.append(.{ neighbor, weight + 1 });
            }
        }
    }
}

pub fn dumpToLog(self: DijkstraMap) void {
    var buf: [2048]u8 = [_]u8{0} ** 2048;
    var writer = std.io.fixedBufferStream(&buf);
    self.write(writer.writer().any()) catch unreachable;
    std.log.debug("Dijkstra Map:\n{s}", .{std.mem.sliceTo(&buf, 0)});
}

fn write(
    self: DijkstraMap,
    writer: std.io.AnyWriter,
) !void {
    for (0..self.region.rows) |row_idx| {
        try writer.writeByte('|');
        for (0..self.region.cols) |col_idx| {
            const place = p.Point{
                .row = @intCast(row_idx + self.region.top_left.row),
                .col = @intCast(col_idx + self.region.top_left.col),
            };
            if (self.vectors.get(place)) |tuple| {
                const char = directionToArrow(tuple[0]);
                try writer.print("{c}{d:2}|", .{ char, tuple[1] });
            } else {
                _ = try writer.write("? 0|");
            }
        }
        try writer.writeByte('\n');
    }
}

inline fn directionToArrow(direction: p.Direction) u8 {
    return switch (direction) {
        .up => '^',
        .right => '>',
        .down => 'v',
        .left => '<',
    };
}

test "vectors for the middle of the empty region 5x5" {
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 5, .cols = 5 };
    const clojure = struct {
        fn noObstacles(_: *const anyopaque, _: p.Point) bool {
            return false;
        }
    };
    const obstacles: Obstacles = .{
        .context = undefined,
        .isObstacleFn = clojure.noObstacles,
    };
    var field = DijkstraMap.init(std.testing.allocator, region, obstacles);
    defer field.deinit();

    try field.calculate(.{ .row = 3, .col = 3 });

    var buf: [512]u8 = [1]u8{0} ** 512;
    var fbs = std.io.fixedBufferStream(&buf);
    try field.write(fbs.writer().any());
    const expected =
        \\|> 4|> 3|v 2|v 3|v 4|
        \\|> 3|> 2|v 1|v 2|v 3|
        \\|> 2|> 1|? 0|< 1|< 2|
        \\|> 3|> 2|^ 1|< 2|< 3|
        \\|> 4|> 3|^ 2|< 3|< 4|
        \\
    ;

    try std.testing.expectEqualStrings(expected, std.mem.sliceTo(&buf, 0));
}

test "vectors for the region with obstacles" {
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 5, .cols = 5 };
    const clojure = struct {

        // .#...
        // .#...
        // .#@#.
        // .#...
        // .....
        fn isObstacle(_: *const anyopaque, place: p.Point) bool {
            return (place.col == 2 and (place.row < 5)) or (place.row == 3 and place.col == 4);
        }
    };
    const obstacles: Obstacles = .{
        .context = undefined,
        .isObstacleFn = clojure.isObstacle,
    };
    var field = DijkstraMap.init(std.testing.allocator, region, obstacles);
    defer field.deinit();

    try field.calculate(.{ .row = 3, .col = 3 });

    var buf: [512]u8 = [1]u8{0} ** 512;
    var fbs = std.io.fixedBufferStream(&buf);
    try field.write(fbs.writer().any());
    const expected =
        \\|v 8|? 0|v 2|v 3|v 4|
        \\|v 7|? 0|v 1|< 2|< 3|
        \\|v 6|? 0|? 0|? 0|v 4|
        \\|v 5|? 0|^ 1|< 2|< 3|
        \\|> 4|> 3|^ 2|< 3|< 4|
        \\
    ;

    try std.testing.expectEqualStrings(expected, std.mem.sliceTo(&buf, 0));
}
