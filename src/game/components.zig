const std = @import("std");
const Preset = @import("Preset.zig").Preset;
const g = @import("game_pkg.zig");
const p = g.primitives;

/// A set of entities ids. Used in the component-containers such as inventory or pile.
const EntitiesSet = struct {
    const Self = @This();

    const UnderlyingMap = std.AutoHashMapUnmanaged(g.Entity, void);
    pub const Iterator = UnderlyingMap.KeyIterator;

    alloc: std.mem.Allocator,
    underlying_map: UnderlyingMap = .empty,

    pub fn empty(alloc: std.mem.Allocator) Self {
        return .{ .alloc = alloc, .underlying_map = .empty };
    }

    pub fn deinit(self: *Self) void {
        self.underlying_map.deinit(self.alloc);
    }

    pub fn clone(self: Self, alloc: std.mem.Allocator) !Self {
        return .{ .alloc = alloc, .underlying_map = try self.underlying_map.clone(alloc) };
    }

    pub fn size(self: Self) usize {
        return self.underlying_map.size;
    }

    pub fn iterator(self: Self) Iterator {
        return self.underlying_map.keyIterator();
    }

    pub fn add(self: *Self, item: g.Entity) !void {
        try self.underlying_map.put(self.alloc, item, {});
    }

    pub fn remove(self: *Self, item: g.Entity) bool {
        return self.underlying_map.remove(item);
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginArray();
        var itr = self.underlying_map.keyIterator();
        while (itr.next()) |entity| {
            try jws.write(entity.id);
        }
        try jws.endArray();
    }

    pub fn jsonParse(alloc: std.mem.Allocator, source: anytype, opts: std.json.ParseOptions) !Self {
        const value = try std.json.Value.jsonParse(alloc, source, opts);
        defer value.array.deinit();
        return try jsonParseFromValue(alloc, value, opts);
    }

    pub fn jsonParseFromValue(alloc: std.mem.Allocator, value: std.json.Value, _: std.json.ParseOptions) !Self {
        var result: Self = .{ .alloc = alloc, .underlying_map = .empty };
        for (value.array.items) |v| {
            try result.underlying_map.put(alloc, .{ .id = @intCast(v.integer) }, {});
        }
        return result;
    }

    pub fn eql(self: Self, other: Self) bool {
        if (self.underlying_map.size != other.underlying_map.size)
            return false;

        var self_itr = self.underlying_map.keyIterator();
        var other_itr = self.underlying_map.keyIterator();
        while (self_itr.next()) |s| {
            while (other_itr.next()) |o| {
                if (!std.meta.eql(s, o))
                    return false;
            }
        }
        return true;
    }
};

pub const Position = struct {
    place: p.Point,
};

pub const Door = struct { state: enum { opened, closed } };

/// Describes how and where something should look.
pub const Sprite = struct {
    codepoint: g.Codepoint,
};

/// The vertical order of the entities on the same place.
/// The sprite with bigger order should be rendered over the sprite with lower.
pub const ZOrder = struct {
    order: enum {
        /// opened doors, ladders, teleports...
        floor,
        /// any dropped items, piles...
        item,
        /// player, enemies, npc, closed doors...
        obstacle,
    },
};

pub const Description = struct {
    preset: g.descriptions.Presets.Keys,

    pub fn name(self: *const Description) []const u8 {
        return g.descriptions.Presets.get(self.preset).name;
    }

    pub fn description(self: *const Description) []const []const u8 {
        return g.descriptions.Presets.get(self.preset).description;
    }
};

pub const Animation = struct {
    pub const FramesPresets = Preset(struct {
        empty: []const g.Codepoint = &[0]g.Codepoint{},
        hit: []const g.Codepoint = &[3]g.Codepoint{ 0, '×', 0 },
        miss: []const g.Codepoint = &[1]g.Codepoint{'.'},
        go_sleep: []const g.Codepoint = &[6]g.Codepoint{ 0, 'z', 'z', 0, 'z', 'z' },
        relax: []const g.Codepoint = &[6]g.Codepoint{ 0, '?', '?', 0, '?', '?' },
        get_angry: []const g.Codepoint = &[6]g.Codepoint{ 0, '!', '!', 0, '!', '!' },
    });

    preset: FramesPresets.Keys,
    current_frame: u8 = 0,
    previous_render_time: c_uint = 0,
    lag: u32 = 0,

    pub fn frame(self: *Animation, now: u32) ?g.Codepoint {
        const frames: []const g.Codepoint = FramesPresets.get(self.preset).*;
        self.lag += now - self.previous_render_time;
        self.previous_render_time = now;
        if (self.lag > g.RENDER_DELAY_MS) {
            self.lag = 0;
            self.current_frame += 1;
        }
        return if (self.current_frame <= frames.len) frames[self.current_frame - 1] else null;
    }
};

/// The ladder to the upper or under level from the current one
pub const Ladder = struct {
    pub const Direction = enum { up, down };
    /// Direction of the ladder
    direction: Direction,
    /// The id of the ladder on this level.
    id: g.Entity,
    /// The id of the ladder on that level.
    target_ladder: g.Entity,

    pub fn inverted(self: Ladder) Ladder {
        return .{
            .direction = if (self.direction == .up) .down else .up,
            .id = self.target_ladder,
            .target_ladder = self.id,
        };
    }
};

pub const Health = struct {
    // The count of maximum hp
    max: u8,
    // The count of the current hp
    current: i16,
};

pub const Speed = struct {
    /// How many move points are needed for moving on the neighbor position
    move_points: u8,

    pub const default: Speed = .{ .move_points = 10 };
};

pub const Pile = struct {
    const Self = @This();

    items: EntitiesSet,

    pub fn empty(alloc: std.mem.Allocator) Pile {
        return .{ .items = .{ .alloc = alloc } };
    }

    pub fn deinit(self: *Pile) void {
        self.items.deinit();
    }

    pub fn clone(self: Pile, alloc: std.mem.Allocator) !Pile {
        return .{ .items = try self.items.clone(alloc) };
    }
};

pub const Inventory = struct {
    const Self = @This();

    items: EntitiesSet,

    pub fn empty(alloc: std.mem.Allocator) Inventory {
        return .{ .items = .{ .alloc = alloc } };
    }

    pub fn deinit(self: *Inventory) void {
        self.items.deinit();
    }

    pub fn clone(self: Inventory, alloc: std.mem.Allocator) !Inventory {
        return .{ .items = try self.items.clone(alloc) };
    }
};

pub const Equipment = struct {
    weapon: ?g.Entity = null,
    light: ?g.Entity = null,

    pub const nothing: Equipment = .{ .weapon = null, .light = null };
};

pub const Weapon = struct {
    min_damage: u8,
    max_damage: u8,

    pub inline fn generateDamage(self: Weapon, rand: std.Random) u8 {
        return if (self.max_damage > self.min_damage)
            rand.uintLessThan(u8, self.max_damage - self.min_damage) + self.min_damage
        else
            self.min_damage;
    }
};

pub const Initiative = struct {
    move_points: g.MovePoints,

    pub const empty: Initiative = .{ .move_points = 0 };
};

pub const EnemyState = enum {
    sleeping,
    walking,
    aggressive,
};

pub const SourceOfLight = struct {
    radius: f16,
};

pub const Components = struct {
    animation: ?Animation = null,
    description: ?Description,
    door: ?Door = null,
    equipment: ?Equipment = null,
    health: ?Health = null,
    initiative: ?Initiative = null,
    inventory: ?Inventory = null,
    ladder: ?Ladder = null,
    pile: ?Pile = null,
    position: ?Position = null,
    source_of_light: ?SourceOfLight = null,
    speed: ?Speed = null,
    sprite: ?Sprite,
    state: ?EnemyState = null,
    weapon: ?Weapon = null,
    z_order: ?ZOrder,
};

test "Components should be serializable" {
    var inventory = Inventory.empty(std.testing.allocator);
    try inventory.items.add(.{ .id = 7 });
    defer inventory.deinit();

    var pile = Pile.empty(std.testing.allocator);
    try pile.items.add(.{ .id = 9 });
    defer pile.deinit();

    // Random components to check serialization:
    const prototype = Components{
        .animation = Animation{ .preset = .hit },
        .description = Description{ .preset = .player },
        .door = Door{ .state = .opened },
        .equipment = Equipment{ .weapon = .{ .id = 1 }, .light = .{ .id = 12 } },
        .health = Health{ .current = 42, .max = 100 },
        .initiative = Initiative{ .move_points = 5 },
        .inventory = inventory,
        .ladder = Ladder{ .id = .{ .id = 2 }, .direction = .down, .target_ladder = .{ .id = 3 } },
        .pile = pile,
        .position = Position{ .place = p.Point.init(12, 42) },
        .source_of_light = SourceOfLight{ .radius = 4 },
        .speed = Speed{ .move_points = 12 },
        .sprite = Sprite{ .codepoint = g.codepoints.human },
        .state = .walking,
        .weapon = Weapon{ .min_damage = 3, .max_damage = 32 },
        .z_order = ZOrder{ .order = .obstacle },
    };

    const buffer: []u8 = try std.json.stringifyAlloc(std.testing.allocator, prototype, .{});
    defer std.testing.allocator.free(buffer);

    const parsed = try std.json.parseFromSlice(Components, std.testing.allocator, buffer, .{});
    defer parsed.deinit();

    try expectEql(prototype, parsed.value);
}

fn expectEql(expected: anytype, actual: anytype) !void {
    try std.testing.expectEqual(@TypeOf(expected), @TypeOf(actual));

    switch (@typeInfo(@TypeOf(expected))) {
        .pointer => try expectEql(expected.*, actual.*),
        .optional => try expectEql(expected.?, actual.?),
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
