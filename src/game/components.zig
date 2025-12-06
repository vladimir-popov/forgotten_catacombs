const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const u = g.utils;

pub const Armor = struct {
    resistance: std.EnumArray(Damage.Type, u8),

    pub fn init(resistances: std.enums.EnumFieldStruct(Damage.Type, u8, 0)) Armor {
        return .{ .resistance = .initDefault(0, resistances) };
    }
};

/// A place in the dungeon where an entity is, and its z-order.
/// A place with zero row and zero column is undefined.
/// **NOTE:** do not replace the whole position. Only the place should be changed during the game,
/// because z-order is a constant property of the entity.
pub const Position = struct {
    place: p.Point,
    /// The vertical order of the entities on the same place.
    /// The sprite with bigger order should be rendered over the sprite with lower.
    zorder: enum {
        /// opened doors, ladders, teleports...
        floor,
        /// any dropped items, piles...
        item,
        /// player, enemies, npc, closed doors...
        obstacle,
    },
};

pub const Door = struct { state: enum { opened, closed } };

/// Describes how and where something should look.
pub const Sprite = struct {
    codepoint: g.Codepoint,
};

pub const Description = struct {
    preset: g.presets.Descriptions.Tag,
};

pub const Animation = struct {
    pub const FramesPresets = u.Preset([]const g.Codepoint, struct {
        empty: []const g.Codepoint = &[_]g.Codepoint{},
        get_angry: []const g.Codepoint = &[_]g.Codepoint{ 0, '!', 0, '!', 0, '!' },
        go_sleep: []const g.Codepoint = &[_]g.Codepoint{ 0, 'z', 0, 'z', 0, 'z' },
        // healing: []const g.Codepoint = &[_]g.Codepoint{ 0, '♥', 0, '♥' },
        healing: []const g.Codepoint = &[_]g.Codepoint{ 0, '+', 0, '+' },
        hit: []const g.Codepoint = &[_]g.Codepoint{ 0, '×', 0 },
        relax: []const g.Codepoint = &[_]g.Codepoint{ 0, '?', 0, '?', 0, '?' },
        // teleport: []const g.Codepoint = &[_]g.Codepoint{ '-', '=', '≡' },
        wait: []const g.Codepoint = &[_]g.Codepoint{ 'z', 'Z', 'z', 'Z' },
    });

    preset: FramesPresets.Tag,
    current_frame: u8 = 0,
    previous_render_time: c_uint = 0,
    /// true means that input should not be handled until all frames of this animation will be played.
    is_blocked: bool = false,

    pub fn frame(self: *Animation, now: u32) ?g.Codepoint {
        const frames = FramesPresets.values.get(self.preset);
        if (now - self.previous_render_time > g.RENDER_DELAY_MS) {
            self.previous_render_time = now;
            self.current_frame += 1;
        }
        // the first invocation is always increments the current_frame.
        // this is way -1 is safe here
        return if (self.current_frame <= frames.len) frames.*[self.current_frame - 1] else null;
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

    pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print(
            "Ladder(id: {d}; direction: {s}; target: {d})",
            .{ self.id.id, @tagName(self.direction), self.target_ladder.id },
        );
    }
};

pub const Health = struct {
    // The count of maximum hp
    max: u8,
    // The count of the current hp
    current: u8,

    pub fn add(self: *Health, value: u8) void {
        self.current += value;
        self.current = @min(self.current, self.max);
    }
};

pub const Speed = struct {
    /// How many move points are needed for moving on the neighbor position
    move_points: u8,

    pub const default: Speed = .{ .move_points = 10 };
};

pub const Pile = struct {
    items: u.EntitiesSet,

    pub fn empty(alloc: std.mem.Allocator) !Pile {
        return .{ .items = try u.EntitiesSet.init(alloc) };
    }

    pub fn deinit(self: *Pile) void {
        self.items.deinit();
    }
};

pub const Inventory = struct {
    items: u.EntitiesSet,

    pub fn empty(alloc: std.mem.Allocator) !Inventory {
        return .{ .items = try u.EntitiesSet.init(alloc) };
    }

    pub fn deinit(self: *Inventory) void {
        self.items.deinit();
    }
};

pub const Price = struct {
    value: u16,
};

pub const Shop = struct {
    // FIXME: this is a very primitive mechanic. it would be better if different items would have different
    // multiplier, and that multiplier would depends on player's characteristics.
    price_multiplier: f16,
    items: u.EntitiesSet,
    balance: u16 = 0,

    pub fn empty(alloc: std.mem.Allocator, price_multiplier: f16, balance: u16) !Shop {
        return .{ .items = try u.EntitiesSet.init(alloc), .price_multiplier = price_multiplier, .balance = balance };
    }

    pub fn deinit(self: *Shop) void {
        self.items.deinit();
        self.price_multiplier = undefined;
    }
};

pub const Wallet = struct {
    money: u16,

    pub const empty: Wallet = .{ .money = 0 };
};

pub const Equipment = struct {
    weapon: ?g.Entity,
    light: ?g.Entity,

    pub const nothing: Equipment = .{ .weapon = null, .light = null };
};

pub const Damage = struct {
    pub const Type = enum { physical, poison, fire, acid };
    damage_type: Type,
    min: u8,
    max: u8,
};

pub const Effect = struct {
    pub const Type = enum { burning, corrosion, healing, poisoninig };
    pub const TypesCount = @typeInfo(Type).@"enum".fields.len;
    effect_type: Type,
    min: u8,
    max: u8,

    pub fn damage(self: Effect) ?Damage {
        const damage_type: ?Damage.Type = switch (self.effect_type) {
            .burning => .fire,
            .corrosion => .acid,
            .poisoninig => .poison,
            .healing => null,
        };
        return if (damage_type) |dt|
            .{ .damage_type = dt, .min = self.min, .max = self.max }
        else
            null;
    }
};

pub const Consumable = struct {
    pub const Type = enum { food, potion };
    consumable_type: Type,
    calories: u8,
};

pub const Rarity = enum(u8) {
    common = 15,
    rare = 10,
    very_rare = 5,
    legendary = 1,
    unique = 0,

    pub const proportions: [std.meta.fields(Rarity).len]u8 = blk: {
        var result: [std.meta.fields(Rarity).len]u8 = undefined;
        for (std.meta.fields(Rarity), 0..) |f, i| {
            result[i] = f.value;
        }
        break :blk result;
    };
};

test Rarity {
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    const rand = prng.random();
    var result: [std.meta.fields(Rarity).len]u8 = @splat(0);
    for (0..255) |_| {
        const i = rand.weightedIndex(u8, &Rarity.proportions);
        result[i] += 1;
    }
    defer std.debug.print(
        \\Common:       {d}
        \\Rare:         {d}
        \\Very rare:    {d}
        \\Legendary:    {d}
        \\Unique:       {d}
        \\
    , .{
        result[0],
        result[1],
        result[2],
        result[3],
        result[4],
    });
    for (1..result.len) |i| {
        try std.testing.expect(result[i - 1] > result[i]);
    }
    try std.testing.expectEqual(0, result[result.len - 1]);
}

pub const Initiative = struct {
    move_points: g.MovePoints,

    pub const empty: Initiative = .{ .move_points = 0 };
};

pub const EnemyState = enum {
    sleeping,
    walking,
    aggressive,
};

pub const Progression = struct {
    /// A numbers of required exp point for level up.
    /// The 0 element is a required amount of exp point to get the
    /// second level.
    pub const Levels: [3]u16 = .{ 500, 1000, 15000 };
    experience: u16 = 0,
    level: u8 = 1,

    pub const first_level: Progression = .{};

    pub fn experienceToNextLevel(self: Progression) u16 {
        return Levels[self.level - 1];
    }
};

pub const Reward = struct {
    /// A number of exp point for killing an enemy first time.
    experience: u16,
};

pub const SourceOfLight = struct {
    radius: f16,
};

pub const Skills = struct {
    pub const empty: Skills = .init(0, 0, 0, 0);

    values: std.enums.EnumArray(g.descriptions.Skills.Enum, i4),

    pub fn init(
        weapon_mastery: i4,
        mechanics: i4,
        stealth: i4,
        echo_of_knowledge: i4,
    ) Skills {
        return .{
            .values = .init(.{
                .weapon_mastery = weapon_mastery,
                .mechanics = mechanics,
                .stealth = stealth,
                .echo_of_knowledge = echo_of_knowledge,
            }),
        };
    }
};

pub const Stats = struct {
    pub const empty: Stats = .init(0, 0, 0, 0, 0);

    strength: i4,
    dexterity: i4,
    perception: i4,
    intelligence: i4,
    constitution: i4,

    pub fn init(
        strength: i4,
        dexterity: i4,
        perception: i4,
        intelligence: i4,
        constitution: i4,
    ) Stats {
        return .{
            .strength = strength,
            .dexterity = dexterity,
            .perception = perception,
            .intelligence = intelligence,
            .constitution = constitution,
        };
    }
};

pub const Weight = struct {
    value: u8,
};

pub const WeaponClass = enum {
    primitive,
    tricky,
    ancient,
};

pub const Components = struct {
    animation: ?Animation = null,
    armor: ?Armor = null,
    consumable: ?Consumable = null,
    damage: ?Damage = null,
    description: ?Description, // must be provided for every entity
    door: ?Door = null,
    effect: ?Effect = null,
    equipment: ?Equipment = null,
    health: ?Health = null,
    initiative: ?Initiative = null,
    inventory: ?Inventory = null,
    ladder: ?Ladder = null,
    pile: ?Pile = null,
    position: ?Position = null,
    price: ?Price = null,
    progression: ?Progression = null,
    rarity: ?Rarity = null,
    reward: ?Reward = null,
    shop: ?Shop = null,
    skills: ?Skills = null,
    stats: ?Stats = null,
    source_of_light: ?SourceOfLight = null,
    speed: ?Speed = null,
    sprite: ?Sprite, // must be provided for every entity
    state: ?EnemyState = null,
    wallet: ?Wallet = null,
    weight: ?Weight = null,
    weapon_class: ?WeaponClass = null,
};
