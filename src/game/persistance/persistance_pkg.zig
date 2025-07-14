//! The persistence layer currently implemented with Json format.
//! Note, that this implementation is order sensitive. It means that fields of every persisted
//! structures must follow the same order on reading in which they were written.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;
const u = g.utils;

pub const Reader = @import("Reader.zig").Reader;
pub const Writer = @import("Writer.zig").Writer;
pub const Loading = @import("Loading.zig");
pub const Saving = @import("Saving.zig");

pub const PATH_TO_SESSION_FILE = "session.json";

pub fn pathToLevelFile(buf: []u8, depth: u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "level_{d}.json", .{depth});
}

test "All components should be serializable" {
    var original_registry = try g.Registry.init(std.testing.allocator);
    errdefer original_registry.deinit();

    var inventory = try c.Inventory.empty(std.testing.allocator);
    try inventory.items.add(.{ .id = 7 });
    defer inventory.deinit();

    var pile = try c.Pile.empty(std.testing.allocator);
    try pile.items.add(.{ .id = 9 });
    defer pile.deinit();

    // Random components to check serialization:
    const expected = c.Components{
        .animation = c.Animation{ .preset = .hit },
        .description = c.Description{ .preset = .player },
        .door = c.Door{ .state = .opened },
        .equipment = c.Equipment{ .weapon = null, .light = .{ .id = 12 } },
        .health = c.Health{ .current = 42, .max = 100 },
        .initiative = c.Initiative{ .move_points = 5 },
        .inventory = inventory,
        .ladder = c.Ladder{ .id = .{ .id = 2 }, .direction = .down, .target_ladder = .{ .id = 3 } },
        .pile = pile,
        .position = c.Position{ .place = p.Point.init(12, 42) },
        .source_of_light = c.SourceOfLight{ .radius = 4 },
        .speed = c.Speed{ .move_points = 12 },
        .sprite = c.Sprite{ .codepoint = g.codepoints.human },
        .state = .walking,
        .weapon = c.Weapon{ .min_damage = 3, .max_damage = 32 },
        .z_order = c.ZOrder{ .order = .obstacle },
    };

    var buffer: [1024]u8 = @splat(0);
    var buffer_writer = std.io.fixedBufferStream(&buffer);
    const underlying_writer = buffer_writer.writer();
    var writer = Writer(@TypeOf(underlying_writer)).init(&original_registry, underlying_writer);

    // when:
    try writer.write(expected);
    original_registry.deinit();

    std.debug.print("{s}\n", .{buffer});

    // then:
    var actual_registry = try g.Registry.init(std.testing.allocator);
    defer actual_registry.deinit();

    var buffer_reader = std.io.fixedBufferStream(&buffer);
    const underlying_reader = buffer_reader.reader();
    var reader = Reader(@TypeOf(underlying_reader)).init(&actual_registry, underlying_reader);

    const actual = try reader.read(c.Components);

    try expectEql(expected, actual);
}

fn expectEql(expected: anytype, actual: anytype) !void {
    try std.testing.expectEqual(@TypeOf(expected), @TypeOf(actual));

    switch (@typeInfo(@TypeOf(expected))) {
        .pointer => try expectEql(expected.*, actual.*),
        .optional => if (expected == null)
            try std.testing.expectEqual(null, actual)
        else
            try expectEql(expected.?, actual.?),
        .@"struct" => |s| inline for (s.fields) |field| {
            if (@hasDecl(@TypeOf(expected), "eql")) {
                try std.testing.expect(expected.eql(actual));
            } else {
                try expectEql(@field(expected, field.name), @field(actual, field.name));
            }
        },
        else => try std.testing.expectEqual(expected, actual),
    }
}
