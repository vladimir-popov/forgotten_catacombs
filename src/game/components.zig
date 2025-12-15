const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const u = g.utils;

pub const Armor = struct {
    pub const zeros: Armor = .{ .resistance = .initFill(.zero) };

    // The min and max inclusive values of absorbed damage
    pub const Defence = struct {
        pub const zero: Defence = .{ .min = 0, .max = 0 };
        min: u8,
        max: u8,
        pub fn init(min: u8, max: u8) Defence {
            return .{ .min = min, .max = max };
        }
    };
    resistance: std.EnumArray(Effect.Type, Defence),

    pub fn init(effs: []const Effect) Armor {
        var self: Armor = zeros;
        for (effs) |effect| {
            self.resistance.set(effect.effect_type, .init(effect.min, effect.max));
        }
        return self;
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

    pub fn init(max: u8) Health {
        return .{ .current = max, .max = max };
    }

    pub fn add(self: *Health, value: u8) void {
        self.current += value;
        self.current = @min(self.current, self.max);
    }
};

pub const Speed = struct {
    /// How many move points are needed for moving on the neighbor position
    move_points: u8,

    pub const default: Speed = .{ .move_points = g.MOVE_POINTS_IN_TURN };
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

pub const Effect = struct {
    pub const Type = enum { physical, burning, corrosion, poisoning, healing };
    pub const TypesCount = @typeInfo(Type).@"enum".fields.len;
    effect_type: Type,
    min: u8,
    max: u8,

    pub fn physical(min: u8, max: u8) Effect {
        return .{ .effect_type = .physical, .min = min, .max = max };
    }

    pub fn burning(min: u8, max: u8) Effect {
        return .{ .effect_type = .burning, .min = min, .max = max };
    }

    pub fn corrosion(min: u8, max: u8) Effect {
        return .{ .effect_type = .corrosion, .min = min, .max = max };
    }

    pub fn poisoning(min: u8, max: u8) Effect {
        return .{ .effect_type = .poisoning, .min = min, .max = max };
    }

    pub fn healing(min: u8, max: u8) Effect {
        return .{ .effect_type = .healing, .min = min, .max = max };
    }

    pub fn modify(self: *Effect, modificator: i8) void {
        self.min = @max(0, modificator + @as(i8, @intCast(self.min)));
        self.max = @max(0, modificator + @as(i8, @intCast(self.max)));
    }
};

pub const Effects = struct {
    buffer: [3]Effect = undefined,
    len: usize = 0,

    pub fn init(effs: []const Effect) Effects {
        var self: Effects = .{};
        self.len = effs.len;
        @memcpy(self.buffer[0..self.len], effs);
        return self;
    }

    pub inline fn items(self: Effects) []const Effect {
        return self.buffer[0..self.len];
    }

    /// - `writer` - as example: `*persistance.Writer(Runtime.FileWriter.Writer)`
    pub fn save(self: Effects, writer: anytype) !void {
        try writer.beginCollection();
        for (self.items()) |effect| {
            try writer.write(effect);
        }
        try writer.endCollection();
    }

    /// - `reader` - as example: `*persistance.Reader(Runtime.FileReader.Reader)`
    pub fn load(reader: anytype) !Effects {
        var self = Effects{};
        try reader.beginCollection();
        while (!try reader.isCollectionEnd()) {
            self.buffer[self.len] = try reader.read(Effect);
            self.len += 1;
        }
        try reader.endCollection();
        return self;
    }
};

pub const Modification = struct {
    modificators: std.EnumMap(Effect.Type, i8),

    /// Example:
    /// ```
    /// .init(.{ .burning = -3 }, true);
    /// ```
    pub fn init(modificators: std.enums.EnumFieldStruct(Effect.Type, i8, 0)) Modification {
        return .{ .modificators = .initFullWithDefault(0, modificators) };
    }

    pub fn applyTo(self: Modification, effects: *Effects) void {
        for (0..effects.len) |i| {
            if (self.modificators.get(effects.buffer[i].effect_type)) |modificator| {
                if (modificator != 0)
                    effects.buffer[i].modify(modificator);
            }
        }
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try writer.write("Modificators{ ");
        const effect_types = std.enums.values(Effect.Type);
        for (effect_types) |effect_type| {
            try writer.print(" {t}={d} ", .{ effect_type, self.modificators.get(effect_type) orelse 0 });
        }
        _ = try writer.write(" }");
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

/// The information about the current amount of experience points, the current level,
/// and the reward for a victor.
pub const Experience = struct {
    const reward_denominator = 10;

    pub const zero: Experience = .{ .experience = 0, .level = 1 };

    level: u4,
    experience: u16,

    pub fn init(experience: u16) Experience {
        return .{ .level = actualLevel(1, experience), .experience = experience };
    }

    pub inline fn reward(reward_exp: u16) Experience {
        return .init(reward_exp * reward_denominator);
    }

    pub fn asReward(self: Experience) u16 {
        return self.experience / reward_denominator;
    }

    pub fn add(self: *Experience, exp: u16) void {
        self.experience +|= exp;
        self.level = actualLevel(self.level, self.experience);
    }

    fn actualLevel(current_level: u4, total_experience: u16) u4 {
        var level = current_level;
        while (g.meta.Levels[level - 1] < total_experience) {
            level += 1;
        }
        return level;
    }
};

pub const SourceOfLight = struct {
    radius: f16,
};

pub const Skills = struct {
    pub const zeros: Skills = .init(0, 0, 0, 0);

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
    pub const zeros: Stats = .init(0, 0, 0, 0, 0);

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
    description: ?Description, // must be provided for every entity
    door: ?Door = null,
    effects: ?Effects = null,
    equipment: ?Equipment = null,
    experience: ?Experience = null,
    health: ?Health = null,
    initiative: ?Initiative = null,
    inventory: ?Inventory = null,
    ladder: ?Ladder = null,
    modification: ?Modification = null,
    pile: ?Pile = null,
    position: ?Position = null,
    price: ?Price = null,
    rarity: ?Rarity = null,
    shop: ?Shop = null,
    skills: ?Skills = null,
    source_of_light: ?SourceOfLight = null,
    speed: ?Speed = null,
    sprite: ?Sprite, // must be provided for every entity
    state: ?EnemyState = null,
    stats: ?Stats = null,
    wallet: ?Wallet = null,
    weapon_class: ?WeaponClass = null,
    weight: ?Weight = null,
};
