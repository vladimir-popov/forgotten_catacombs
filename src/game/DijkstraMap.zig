//! This is a limited area with precalculated directions lead to the player.
const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;

const DijkstraMap = @This();

const Vector = struct { direction: p.Direction, distance: u8 };
const VectorsMap = std.AutoHashMapUnmanaged(p.Point, Vector);

pub const Obstacles = struct {
    context: *const anyopaque,
    isObstacleFn: *const fn (ptr: *const anyopaque, place: p.Point) bool,

    pub inline fn isObstacle(self: Obstacles, place: p.Point) bool {
        return self.isObstacleFn(self.context, place);
    }
};

alloc: std.mem.Allocator,
region: p.Region,
/// The Dijkstra map that provides an optimal direction to the player, and counts of moves
/// needed to achieve the player in that direction.
/// The weight == 0 means that the place is unreachable and has some obstacle.
vectors: VectorsMap,
obstacles: Obstacles,

pub fn init(alloc: std.mem.Allocator, region: p.Region, obstacles: Obstacles) DijkstraMap {
    return .{ .alloc = alloc, .vectors = .empty, .region = region, .obstacles = obstacles };
}

pub fn deinit(self: *DijkstraMap) void {
    self.vectors.deinit(self.alloc);
}

pub fn calculate(self: *DijkstraMap, target: p.Point) !void {
    var openned: std.ArrayListUnmanaged(struct { p.Point, u8 }) = .empty;
    defer openned.deinit(self.alloc);

    self.vectors.clearRetainingCapacity();

    try openned.append(self.alloc, .{ target, 0 });
    while (openned.pop()) |tuple| {
        const weight: u8 = tuple[1];
        for (&[_]p.Direction{ .left, .up, .right, .down }) |direction| {
            const neighbor = tuple[0].movedTo(direction);
            if (!self.region.containsPoint(neighbor) or neighbor.eql(target) or self.obstacles.isObstacle(neighbor))
                continue;

            const gop = try self.vectors.getOrPut(self.alloc, neighbor);
            if (!gop.found_existing or gop.value_ptr.distance > weight + 1) {
                gop.value_ptr.* = .{ .direction = direction.opposite(), .distance = weight + 1 };
                try openned.append(self.alloc, .{ neighbor, weight + 1 });
            }
        }
    }
}

pub fn dumpToLog(self: DijkstraMap) void {
    var buf: [2048]u8 = [_]u8{0} ** 2048;
    var writer = std.io.fixedBufferStream(&buf);
    self.write(writer.writer().any()) catch unreachable;
    std.log.debug("Dijkstra Map ({any}):\n{s}", .{ self.region, std.mem.sliceTo(&buf, 0) });
}

fn write(
    self: DijkstraMap,
    writer: std.io.AnyWriter,
) !void {
    try writer.print("   |", .{});
    for (0..self.region.cols) |col_idx| {
        try writer.print("{d:3}|", .{col_idx + 1});
    }
    try writer.writeByte('\n');
    for (0..self.region.rows) |row_idx| {
        try writer.print("{d:3}|", .{row_idx + 1});
        for (0..self.region.cols) |col_idx| {
            const place = p.Point{
                .row = @intCast(row_idx + self.region.top_left.row),
                .col = @intCast(col_idx + self.region.top_left.col),
            };
            if (self.vectors.get(place)) |vector| {
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
