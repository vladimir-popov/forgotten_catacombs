const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const u = g.utils;

/// A place in the dungeon where an entity is, and its z-order.
/// A place with zero row and zero column is undefined.
/// **NOTE:** do not replace the whole position. Only the place should be changed during the game,
/// because z-order is a constant property of the entity.
pub const Position = struct {
    pub const ZOrder = enum {
        pub const count = @typeInfo(ZOrder).@"enum".fields.len;

        pub const indexes: [count]u8 = .{ 0, 1, 2 };

        /// opened doors, ladders, teleports...
        floor,
        /// any dropped items, traps, piles...
        item,
        /// player, enemies, npc, closed doors...
        obstacle,

        pub inline fn index(self: ZOrder) u4 {
            return @intFromEnum(self);
        }
    };

    place: p.Point,
    /// The vertical order of the entities on the same place.
    /// The sprite with bigger order should be rendered over the sprite with lower.
    zorder: ZOrder,
};

pub const Door = struct { state: enum { opened, closed } };

/// Describes how and where something should look.
pub const Sprite = struct {
    codepoint: g.Codepoint,
};

pub const Description = struct {
    pub const Preset = g.utils.Preset(g.descriptions.Description, g.descriptions);

    preset: Preset.Tag,
};

pub const Animation = struct {
    // Keep in mind, that the last frame can be shown till the player's input.
    // Prefer to use 0 as the last frame.
    pub const FramesPresets = u.Preset([]const g.Codepoint, struct {
        empty: []const g.Codepoint = &[_]g.Codepoint{},
        get_angry: []const g.Codepoint = &[_]g.Codepoint{ '!', 0, '!', 0, '!', 0 },
        go_sleep: []const g.Codepoint = &[_]g.Codepoint{ 'z', 0, 'z', 0, 'z', 0 },
        // healing: []const g.Codepoint = &[_]g.Codepoint{ 0, '♥', 0, '♥' },
        healing: []const g.Codepoint = &[_]g.Codepoint{ '+', 0, '+', 0 },
        hit: []const g.Codepoint = &[_]g.Codepoint{ '×', 0 },
        relax: []const g.Codepoint = &[_]g.Codepoint{ '?', 0, '?', 0, '?', 0 },
        // teleport: []const g.Codepoint = &[_]g.Codepoint{ '-', '=', '≡' },
        wait: []const g.Codepoint = &[_]g.Codepoint{ 'z', 'Z', 'z', 'Z', 0 },
    });

    preset: FramesPresets.Tag,
    current_frame: u8 = 0,
    previous_render_time: u64 = 0,
    /// true means that input should not be handled until all frames of this animation will be played.
    is_blocked: bool = false,

    pub fn frame(self: *Animation, now: u64) ?g.Codepoint {
        const frames = FramesPresets.fields.get(self.preset);
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

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            "Ladder(id: {d}; direction: {s}; target: {d})",
            .{ self.id.id, @tagName(self.direction), self.target_ladder.id },
        );
    }
};

pub const Health = struct {
    // The count of maximum hit points
    max: u8,
    // The count of the current hit points
    current_hp: u8,

    pub fn init(max: u8) Health {
        return .{ .current_hp = max, .max = max };
    }

    pub fn add(self: *Health, value: u8) void {
        self.current_hp += value;
        self.current_hp = @min(self.current_hp, self.max);
    }
};

pub const Regeneration = struct {
    pub const regular: Regeneration = .{ .turns_to_increase = 20 };

    turns_to_increase: u8,
    accumulated_turns: u8 = 0,
};

pub const Speed = struct {
    /// How many move points are needed for moving on the neighbor position
    move_points: g.MovePoints,

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

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(".{{ .items = {f} }}", .{self.items});
    }
};

pub const Price = struct {
    value: u16,
};

pub const Shop = struct {
    // FIXME: this is a very primitive mechanic. it would be better if different items would have different
    // multiplier, and that multiplier would depends on player's characteristics.
    price_multiplier: f32,
    items: u.EntitiesSet,
    /// This seed is used to generate items for selling.
    seed: u64,
    balance: u16 = 0,

    pub fn empty(alloc: std.mem.Allocator, price_multiplier: f32, balance: u16, seed: u64) !Shop {
        return .{
            .items = try u.EntitiesSet.init(alloc),
            .price_multiplier = price_multiplier,
            .balance = balance,
            .seed = seed,
        };
    }

    pub fn deinit(self: *Shop) void {
        self.items.deinit();
        self.price_multiplier = undefined;
        self.seed = undefined;
    }
};

pub const Wallet = struct {
    money: u16,

    pub const empty: Wallet = .{ .money = 0 };
};

pub const Equipment = struct {
    weapon: ?g.Entity,
    light: ?g.Entity,
    ammunition: ?g.Entity,
    armor: ?g.Entity,

    pub const nothing: Equipment = .{ .weapon = null, .light = null, .ammunition = null, .armor = null };
};

pub const Ammunition = struct {
    pub const Type = enum { arrows, bolts };
    amount: u8,
    ammunition_type: Type,

    pub fn arrows(amount: u8) Ammunition {
        return .{ .amount = amount, .ammunition_type = .arrows };
    }

    pub fn bolts(amount: u8) Ammunition {
        return .{ .amount = amount, .ammunition_type = .bolts };
    }
};

pub const Weapon = struct {
    /// The damage depends on the weapon class
    pub const Class = enum {
        /// The strength is used
        primitive,
        /// The dexterity is used
        tricky,
        /// The intelligence is used
        ancient,
    };
    class: Class,
    /// A type of required ammunition.
    /// The null means that the weapon is melee.
    ammunition_type: ?Ammunition.Type,
    max_distance: u8,
    damage: Effects,

    pub fn melee(class: Class, damage: Effects) Weapon {
        return .{ .max_distance = 1, .ammunition_type = null, .class = class, .damage = damage };
    }

    pub fn ranged(max_distance: u8, ammunition_type: Ammunition.Type, class: Class, damage: Effects) Weapon {
        std.debug.assert(max_distance > 1);
        return .{ .max_distance = max_distance, .ammunition_type = ammunition_type, .class = class, .damage = damage };
    }
};

// THIS IS NOT A COMPONENT!
pub const Effects = struct {
    pub const Type = enum { physical, fire, acid, poison, heal };
    pub const TypesCount = @typeInfo(Type).@"enum".fields.len;
    /// Example:
    /// ```
    /// .{ .fire = .{ .min = 0, .max = 3 } };
    /// ```
    pub const InitStruct = std.enums.EnumFieldStruct(Type, ?p.Range(u8), @as(?p.Range(u8), null));

    pub const no_effects: Effects = .{ .values = .initFull(.empty) };

    pub const proportions: [TypesCount]u8 = blk: {
        var arr: [TypesCount]u8 = undefined;
        @memset(&arr, 0);
        arr[@intFromEnum(Type.physical)] = 20;
        arr[@intFromEnum(Type.fire)] = 8;
        arr[@intFromEnum(Type.poison)] = 10;
        arr[@intFromEnum(Type.acid)] = 5;
        break :blk arr;
    };

    values: std.EnumMap(Type, p.Range(u8)),

    /// Example:
    /// ```
    /// .init(.{ .fire = .{ .min = 0, .max = 3 } });
    /// ```
    pub fn effects(values: std.enums.EnumFieldStruct(Type, ?p.Range(u8), @as(?p.Range(u8), null))) Effects {
        return .{ .values = .init(values) };
    }

    /// Adds the modificator to min and max values of the effect with specified type.
    pub fn modify(self: *Effects, effect_type: Type, modificator: i8) void {
        if (self.values.getPtr(effect_type)) |values| {
            values.min = @max(0, @as(i8, @intCast(values.min)) + modificator);
            values.max = @max(0, @as(i8, @intCast(values.max)) + modificator);
        } else if (modificator > 0) {
            self.values.put(effect_type, .range(0, @intCast(modificator)));
        }
    }

    pub fn chooseRandomType(rand: std.Random) Type {
        return @enumFromInt(rand.weightedIndex(u8, &proportions));
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try writer.write("Effects{ ");
        const effect_types = std.enums.values(Effects.Type);
        for (effect_types) |effect_type| {
            try writer.print("{t}={any}, ", .{ effect_type, self.values.get(effect_type) });
        }
        _ = try writer.write(" }");
    }
};

pub const Protection = struct {
    pub const zeros: Protection = .{ .resistance = .no_effects };

    resistance: Effects,

    pub fn init(values: Effects.InitStruct) Protection {
        return .{ .resistance = .effects(values) };
    }
};

pub const Modification = struct {
    modificators: std.EnumMap(Effects.Type, i8),

    /// Example:
    /// ```
    /// .init(.{ .fire = -3 });
    /// ```
    pub fn init(modificators: std.enums.EnumFieldStruct(Effects.Type, ?i8, @as(?i8, null))) Modification {
        return .{ .modificators = .init(modificators) };
    }

    pub fn applyTo(self: *Modification, effects: *Effects) void {
        var itr = self.modificators.iterator();
        while (itr.next()) |modificator| {
            effects.modify(modificator.key, modificator.value.*);
        }
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try writer.write("Modificators{ ");
        const effect_types = std.enums.values(Effects.Type);
        for (effect_types) |effect_type| {
            try writer.print("{t}={d}, ", .{ effect_type, self.modificators.get(effect_type) orelse 0 });
        }
        _ = try writer.write(" }");
    }
};

pub const Consumable = struct {
    pub const Type = enum { food, potion };
    consumable_type: Type,
    calories: u16,
    effects: Effects = .no_effects,

    pub fn food(calories: u16) Consumable {
        return .{ .consumable_type = .food, .calories = calories };
    }

    pub fn potion(effects: Effects.InitStruct, calories: u16) Consumable {
        return .{ .consumable_type = .potion, .calories = calories, .effects = .effects(effects) };
    }
};

pub const Hunger = struct {
    pub const Level = enum {
        well_fed,
        hunger,
        severe_hunger,
        critical_starvation,

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            _ = switch (self) {
                .well_fed => try writer.write(""),
                .hunger => try writer.write("Hungry"),
                .severe_hunger => try writer.write("Severely hungry"),
                .critical_starvation => try writer.write("Critically starved"),
            };
        }
    };

    pub const well_fed: Hunger = .{ .turns_after_eating = 0 };

    turns_after_eating: u16,

    pub fn level(self: Hunger) Level {
        return switch (self.turns_after_eating) {
            0...1000 => .well_fed,
            1001...1850 => .hunger,
            1851...2500 => .severe_hunger,
            else => .critical_starvation,
        };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            ".{{ .turns_after_eating = {d}, .level() = {t} }}",
            .{ self.turns_after_eating, self.level() },
        );
    }
};

pub const LevelUp = struct {
    /// The last level handled level.
    /// For example, it's possible to get level 2, 3 and 4 before handle any of them.
    /// The player will have the level 4, but the `last_handled_level` will be 1.
    /// When level up will be handled once, the `last_handled_level` become 2 and so on.
    last_handled_level: u4,
};

/// The chance of appearing an item somewhere (shop, dungeon, reward) depends on its tear and
/// player's level. The high level tiers are for high level players. But, items with zero tear can
/// appear at any moment. It makes possible to find something like arrows during the whole game.
/// An approximate correlation between player's level and item's tear looks like this:
/// tier 1 is for player with level between 1 and 4;
/// tier 2 is for player with level between 5 and 9;
/// and so on.
pub const Tier = struct {
    value: u4,
};

pub const Rarity = enum(u8) {
    common = 15,
    rare = 10,
    very_rare = 5,
    legendary = 1,
    unique = 0,

    const proportions: [std.meta.fields(Rarity).len]u8 = blk: {
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
        return .{ .level = g.meta.actualLevel(1, experience), .experience = experience };
    }

    pub inline fn reward(reward_exp: u16) Experience {
        return .init(reward_exp * reward_denominator);
    }

    pub fn asReward(self: Experience) u16 {
        return self.experience / reward_denominator;
    }
};

pub const SourceOfLight = struct {
    radius: f32,
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

pub const Trap = struct {
    /// The likelihood of detecting and disarming the trap depend on how powerful the trap is.
    /// The trap with power 0 is always visible and easy to disarm.
    power: u3,
    effect: Effects.Type,
    /// The turn when its visibility was checked last time
    last_checked_turn: u32 = 0,
};

pub const Weight = struct {
    value: u8,
};

pub const Components = struct {
    ammunition: ?Ammunition = null,
    animation: ?Animation = null,
    consumable: ?Consumable = null,
    description: ?Description, // must be provided for every entity
    door: ?Door = null,
    equipment: ?Equipment = null,
    experience: ?Experience = null,
    health: ?Health = null,
    hunger: ?Hunger = null,
    initiative: ?Initiative = null,
    inventory: ?Inventory = null,
    ladder: ?Ladder = null,
    level_up: ?LevelUp = null,
    modification: ?Modification = null,
    pile: ?Pile = null,
    position: ?Position = null,
    price: ?Price = null,
    protection: ?Protection = null,
    rarity: ?Rarity = null,
    regeneration: ?Regeneration = null,
    shop: ?Shop = null,
    skills: ?Skills = null,
    source_of_light: ?SourceOfLight = null,
    speed: ?Speed = null,
    sprite: ?Sprite, // must be provided for every entity
    state: ?EnemyState = null,
    stats: ?Stats = null,
    tier: ?Tier = null,
    trap: ?Trap = null,
    wallet: ?Wallet = null,
    weapon: ?Weapon = null,
    weight: ?Weight = null,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try writer.write("Components {\n");
        const fields = std.meta.fields(Components);
        inline for (fields) |field| {
            if (@field(self, field.name)) |value| {
                if (@hasDecl(@TypeOf(value), "format")) {
                    try writer.print("    {s}: {f}\n", .{ field.name, value });
                } else {
                    try writer.print("    {s}: {any}\n", .{ field.name, value });
                }
            }
        }
        try writer.writeByte('}');
    }
};
