//! This is a limited area with precalculated directions lead to the player
const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;

const log = std.log.scoped(.vector_field);

const VectorField = @This();

const VectorsMap = std.AutoHashMap(p.Point, struct { p.Direction, u8 });

region: p.Region,
vectors: VectorsMap,

pub fn init(alloc: std.mem.Allocator, region: p.Region) VectorField {
    return .{ .vectors = VectorsMap.init(alloc), .region = region };
}

pub fn deinit(self: *VectorField) void {
    self.vectors.deinit();
}

pub fn calculate(self: *VectorField, target: p.Point) !void {
    var openned = std.ArrayList(struct { p.Point, u8 }).init(self.vectors.allocator);
    defer openned.deinit();

    try openned.append(.{ target, 0 });
    while (openned.popOrNull()) |tuple| {
        const place = tuple[0];
        const weight: u8 = tuple[1];
        for (&[_]p.Direction{ .left, .up, .right, .down }) |direction| {
            const neighbor = place.movedTo(direction);
            if (!self.region.containsPoint(neighbor) or neighbor.eql(target)) continue;

            const gop = try self.vectors.getOrPut(neighbor);
            if (!gop.found_existing or gop.value_ptr[1] > weight + 1) {
                gop.value_ptr.* = .{ direction.opposite(), weight + 1 };
                try openned.append(.{ neighbor, weight + 1 });
            }
        }
    }
}

pub fn dumpToLog(self: VectorField) void {
    var buf: [512]u8 = undefined;
    const real_size: usize = @as(usize, @intCast(self.region.rows)) * (self.region.cols + 1);
    var writer = std.io.fixedBufferStream(&buf);
    self.write(writer.writer().any()) catch unreachable;
    log.debug("VectorField:\n{s}", .{buf[0..real_size]});
}

fn write(
    self: VectorField,
    writer: std.io.AnyWriter,
) !void {
    var itr = self.region.cells();
    var col: u8 = 0;
    while (itr.next()) |place| {
        if (self.vectors.get(place)) |tuple| {
            const char = directionToArrow(tuple[0]);
            try writer.print("|{c}{d:2}|", .{ char, tuple[1] });
        } else {
            _ = try writer.write("|? 0|");
        }
        col = if (col < self.region.cols - 1) col + 1 else 0;
        if (col == 0) try writer.writeByte('\n');
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

test "vectors for the middle of the range 5x5" {
    var field = VectorField.init(std.testing.allocator, .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 5, .cols = 5 });
    defer field.deinit();

    try field.calculate(.{ .row = 3, .col = 3 });

    var buf: [512]u8 = [1]u8{0} ** 512;
    var fbs = std.io.fixedBufferStream(&buf);
    try field.write(fbs.writer().any());
    const expected =
        \\|> 4||> 3||v 2||v 3||v 4|
        \\|> 3||> 2||v 1||v 2||v 3|
        \\|> 2||> 1||? 0||< 1||< 2|
        \\|> 3||> 2||^ 1||< 2||< 3|
        \\|> 4||> 3||^ 2||< 3||< 4|
        \\
    ;

    try std.testing.expectEqualStrings(expected, std.mem.sliceTo(&buf, 0));
}
