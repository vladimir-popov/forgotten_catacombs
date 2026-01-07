//! This is a limited area with precalculated directions lead to the player.
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

pub const Vector = struct { direction: p.Direction, distance: u8 };
pub const VectorsMap = std.AutoHashMapUnmanaged(p.Point, Vector);

pub const Obstacles = struct {
    context: *const anyopaque,
    isObstacleFn: *const fn (ptr: *const anyopaque, place: p.Point) bool,

    pub inline fn isObstacle(self: Obstacles, place: p.Point) bool {
        return self.isObstacleFn(self.context, place);
    }
};

/// Calculates the Dijkstra map that provides an optimal direction to the player and counts of moves
/// needed to achieve the player in that direction.
/// The weight == 0 means that the place is unreachable and has some obstacle.
/// The map will contains all points from the passed region.
pub fn calculate(
    alloc: std.mem.Allocator, // FIXME: avoid using allocator here
    map: *VectorsMap,
    region: p.Region,
    obstacles: Obstacles,
    target: p.Point,
) !void {
    var openned: std.ArrayListUnmanaged(struct { p.Point, u8 }) = .empty;
    defer openned.deinit(alloc);

    if (map.size > 0)
        map.clearRetainingCapacity();

    try openned.append(alloc, .{ target, 0 });
    while (openned.pop()) |tuple| {
        const weight: u8 = tuple[1];
        for (&[_]p.Direction{ .left, .up, .right, .down }) |direction| {
            const neighbor = tuple[0].movedTo(direction);
            if (!region.containsPoint(neighbor) or neighbor.eql(target) or obstacles.isObstacle(neighbor))
                continue;

            const gop = try map.getOrPut(alloc, neighbor);
            if (!gop.found_existing or gop.value_ptr.distance > weight + 1) {
                gop.value_ptr.* = .{ .direction = direction.opposite(), .distance = weight + 1 };
                try openned.append(alloc, .{ neighbor, weight + 1 });
            }
        }
    }
}

pub fn dumpToLog(map: VectorsMap, region: p.Region) void {
    var buf: [2048]u8 = [_]u8{0} ** 2048;
    var writer = std.Io.Writer.fixed(&buf);
    write(map, &writer, region) catch unreachable;
    std.log.debug("Dijkstra Map ({any}):\n{s}", .{ region, writer.buffered() });
}

/// Iterates over all points inside the passed region and writes a content for them
/// from the map of vectors. The passed region may differ from the region used to fill the map of
/// vectors. If the map doesn't contain some point, same result as for unreachable place will be written.
fn write(map: VectorsMap, writer: *std.Io.Writer, region: p.Region) !void {
    try writer.print("   |", .{});
    for (0..region.cols) |col_idx| {
        try writer.print("{d:3}|", .{col_idx + 1});
    }
    try writer.writeByte('\n');
    for (0..region.rows) |row_idx| {
        try writer.print("{d:3}|", .{row_idx + 1});
        for (0..region.cols) |col_idx| {
            const place = p.Point{
                .row = @intCast(row_idx + region.top_left.row),
                .col = @intCast(col_idx + region.top_left.col),
            };
            if (map.get(place)) |vector| {
                const char = directionToArrow(vector.direction);
                try writer.print("{c}{d:2}|", .{ char, vector.distance });
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

    var map: VectorsMap = .empty;
    defer map.deinit(std.testing.allocator);
    try calculate(std.testing.allocator, &map, region, obstacles, .{ .row = 3, .col = 3 });

    var buf: [512]u8 = [1]u8{0} ** 512;
    var writer = std.Io.Writer.fixed(&buf);
    try write(map, &writer, region);
    const expected =
        \\   |  1|  2|  3|  4|  5|
        \\  1|> 4|> 3|v 2|v 3|v 4|
        \\  2|> 3|> 2|v 1|v 2|v 3|
        \\  3|> 2|> 1|? 0|< 1|< 2|
        \\  4|> 3|> 2|^ 1|< 2|< 3|
        \\  5|> 4|> 3|^ 2|< 3|< 4|
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
    var map: VectorsMap = .empty;
    defer map.deinit(std.testing.allocator);
    try calculate(std.testing.allocator, &map, region, obstacles, .{ .row = 3, .col = 3 });

    var buf: [512]u8 = [1]u8{0} ** 512;
    var writer = std.Io.Writer.fixed(&buf);
    try write(map, &writer, region);
    const expected =
        \\   |  1|  2|  3|  4|  5|
        \\  1|v 8|? 0|v 2|v 3|v 4|
        \\  2|v 7|? 0|v 1|< 2|< 3|
        \\  3|v 6|? 0|? 0|? 0|v 4|
        \\  4|v 5|? 0|^ 1|< 2|< 3|
        \\  5|> 4|> 3|^ 2|< 3|< 4|
        \\
    ;

    try std.testing.expectEqualStrings(expected, std.mem.sliceTo(&buf, 0));
}
