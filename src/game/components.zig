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
    pub const Preset = g.utils.Preset(g.Description, g.descriptions);

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
    moving_speed: g.MovePoints,
    /// How many move points are needed to hit an enemy
    atack_speed: g.MovePoints,

    pub const default: Speed = .{ .moving_speed = g.MOVE_POINTS_IN_TURN, .atack_speed = g.MOVE_POINTS_IN_TURN };
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

    pub inline fn multiply(self: *const Price, k: f32) u16 {
        const valuef: f32 = @floatFromInt(self.value);
        const result: u16 = @intFromFloat(valuef * k);
        return @max(result, 0);
    }
};

pub const Shop = struct {
    items: u.EntitiesSet,

    pub fn empty(alloc: std.mem.Allocator) !Shop {
        return .{ .items = try u.EntitiesSet.init(alloc) };
    }

    pub fn deinit(self: *Shop) void {
        self.items.deinit();
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
    pub const Type = enum { arrows, bolts, bullets };
    amount: u8,
    ammunition_type: Type,

    pub fn arrows(amount: u8) Ammunition {
        return .{ .amount = amount, .ammunition_type = .arrows };
    }

    pub fn bolts(amount: u8) Ammunition {
        return .{ .amount = amount, .ammunition_type = .bolts };
    }

    pub fn bullets(amount: u8) Ammunition {
        return .{ .amount = amount, .ammunition_type = .bullets };
    }
};

// THESE ARE NOT COMPONENTS
pub const Resistance = enum { weak, normal, resist };

/// Bonuses for a weapon, or weaknesses/resistances for am armor.
pub const ElementalEffect = enum { fire, acid, poison };

/// The enum with all possible modification types.
pub const Modification = g.utils.MergeEnums(.{
    ElementalEffect,
    Stats.Stat,
    enum { speed, attack },
});

/// A wrapper with additional methods around the std.enums.EnumSet(Modification)
pub const Modifications = struct {
    items: std.enums.EnumSet(Modification),

    inline fn cast(modification: anytype) Modification {
        const idx_shift = switch (@TypeOf(modification)) {
            Modification, ElementalEffect => 0,
            Stats.Stat => std.enums.values(ElementalEffect).len,
            enum { speed, attack } => std.enums.values(ElementalEffect).len + std.enums.values(Stats.Stat).len,
            else => @compileError(
                std.fmt.comptimePrint(
                    "Unexpected modification type {any} of {any}",
                    .{ @TypeOf(modification), modification },
                ),
            ),
        };
        const idx = @intFromEnum(modification) + idx_shift;
        return @enumFromInt(idx);
    }

    pub fn initEmpty() Modifications {
        return .{ .items = .initEmpty() };
    }

    pub fn init(init_modifications: []const Modification) Modifications {
        var self = Modifications.initEmpty();
        for (init_modifications) |modification| {
            _ = self.add(modification);
        }
        return self;
    }

    pub fn contains(self: Modifications, modification: anytype) bool {
        return self.items.contains(cast(modification));
    }

    /// Inserts the modification and return true, if it was a new modification, or false if such
    /// modification was already in the set.
    pub fn add(self: *Modifications, modification: anytype) bool {
        if (self.items.contains(modification))
            return false;

        self.items.insert(cast(modification));
        return true;
    }

    pub fn remove(self: *Modifications, modification: anytype) void {
        self.items.remove(cast(modification));
    }

    pub fn iterator(self: Modifications) std.enums.EnumSet(Modification).Iterator {
        return self.items.iterator();
    }

    fn actualizeProportions(self: Modifications, proportions: []u8) []u8 {
        for (std.enums.values(Modification), 0..) |modification, i| {
            if (self.contains(modification))
                proportions[i] = 0;
        }
        return proportions;
    }
};
//

pub const Improvements = struct {
    modifications: Modifications,

    pub const empty: Improvements = .{ .modifications = .initEmpty() };

    const all_proportions: [std.enums.values(Modification).len]u8 = blk: {
        var ps: [std.enums.values(Modification).len]u8 = @splat(5);
        ps[@intFromEnum(Modification.fire)] = 10;
        ps[@intFromEnum(Modification.poison)] = 10;
        ps[@intFromEnum(Modification.acid)] = 10;
        ps[@intFromEnum(Modification.speed)] = 3;
        ps[@intFromEnum(Modification.attack)] = 3;
        break :blk ps;
    };

    /// Returns a random modification absent in the current set, or null.
    pub fn chooseRandomNew(self: Improvements, rand: std.Random) ?Modification {
        var proportions: [std.enums.values(Modification).len]u8 = all_proportions;
        _ = self.modifications.actualizeProportions(&proportions);
        if (std.mem.max(u8, &proportions) == 0)
            return null
        else
            return @enumFromInt(rand.weightedIndex(u8, &proportions));
    }
};

pub const Breakages = struct {
    modifications: Modifications,

    pub const empty: Breakages = .{ .modifications = .initEmpty() };

    const all_proportions: [std.enums.values(Modification).len]u8 = blk: {
        var proportions: [std.enums.values(Modification).len]u8 = @splat(5);
        proportions[@intFromEnum(Modification.fire)] = 10;
        proportions[@intFromEnum(Modification.poison)] = 10;
        proportions[@intFromEnum(Modification.acid)] = 10;
        proportions[@intFromEnum(Modification.speed)] = 7;
        proportions[@intFromEnum(Modification.attack)] = 7;
        break :blk proportions;
    };

    /// Returns a random modification absent in the current set, or null.
    pub fn chooseRandomNew(self: Breakages, rand: std.Random, is_for_weapon: bool) ?Modification {
        var proportions: [std.enums.values(Modification).len]u8 = all_proportions;
        _ = self.modifications.actualizeProportions(&proportions);
        if (is_for_weapon) {
            proportions[@intFromEnum(Modification.fire)] = 0;
            proportions[@intFromEnum(Modification.poison)] = 0;
            proportions[@intFromEnum(Modification.acid)] = 0;
        }
        if (std.mem.max(u8, &proportions) == 0)
            return null
        else
            return @enumFromInt(rand.weightedIndex(u8, &proportions));
    }
};

pub const Weapon = struct {
    /// The damage depends on the weapon class
    pub const Class = enum {
        /// No bonuses
        native,
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
    damage: p.Range(u8),
    // Always known effects like the `fire` on a torch
    effects: std.EnumSet(ElementalEffect) = .{},

    pub fn melee(class: Class, damage: p.Range(u8)) Weapon {
        return .{ .max_distance = 1, .ammunition_type = null, .class = class, .damage = damage };
    }

    pub fn meleeWithEffect(class: Class, damage: p.Range(u8), effect: ElementalEffect) Weapon {
        var effs: std.EnumSet(ElementalEffect) = .{};
        effs.insert(effect);
        return .{ .max_distance = 1, .ammunition_type = null, .class = class, .damage = damage, .effects = effs };
    }

    pub fn ranged(max_distance: u8, ammunition_type: Ammunition.Type, class: Class, damage: p.Range(u8)) Weapon {
        std.debug.assert(max_distance > 1);
        return .{ .max_distance = max_distance, .ammunition_type = ammunition_type, .class = class, .damage = damage };
    }
};

pub const Armor = struct {
    pub const zeros = Armor{ .protection = p.Range(u8).range(0, 0) };

    protection: p.Range(u8),
};

/// The property of a food with calories.
pub const Consumable = struct {
    calories: u16,
};

pub const Potion = enum {
    healing,
    poison,
    oil,
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

pub const Initiative = struct {
    move_points: g.MovePoints,
    /// How many move points the player or an enemy spent within the last turn.
    /// We need it to count completed cycles.
    spent_move_points: g.MovePoints = 0,

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
    charge: u16,
    max_charge: u16,
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
    pub const Stat = enum {
        strength,
        dexterity,
        perception,
        intelligence,
        constitution,
    };
    pub const zeros: Stats = .init(0, 0, 0, 0, 0);

    values: std.EnumMap(Stat, i4),

    pub inline fn init(
        strength: i4,
        dexterity: i4,
        perception: i4,
        intelligence: i4,
        constitution: i4,
    ) Stats {
        return .{
            .values = .init(.{
                .strength = strength,
                .dexterity = dexterity,
                .perception = perception,
                .intelligence = intelligence,
                .constitution = constitution,
            }),
        };
    }

    pub inline fn get(self: Stats, key: Stat) i4 {
        return self.values.get(key) orelse 0;
    }

    pub fn add(self: *Stats, stat: Stat, value: i4) void {
        const old = self.get(stat);
        self.values.put(stat, old + value);
    }

    pub fn merge(self: *Stats, other: Stats) void {
        for (std.enums.values(Stat)) |stat| {
            const v = other.get(stat);
            self.add(stat, v);
        }
    }
};

pub const Poison = struct {
    value: u8,
};

pub const Trap = struct {
    /// The likelihood of detecting and disarming the trap depend on how powerful the trap is.
    power: u2,
    /// The turn when its visibility was checked last time
    last_checked_cycle: u32 = 0,

    pub fn damagePercent(self: *const Trap) p.Range(u8) {
        return switch (self.power) {
            0 => p.Range(u8).range(5, 8),
            1 => p.Range(u8).range(10, 15),
            2 => p.Range(u8).range(18, 25),
            3 => p.Range(u8).range(30, 45),
        };
    }
};

pub const Components = struct {
    ammunition: ?Ammunition = null,
    animation: ?Animation = null,
    armor: ?Armor = null,
    breakages: ?Breakages = null,
    consumable: ?Consumable = null,
    description: ?Description, // must be provided for every entity
    door: ?Door = null,
    equipment: ?Equipment = null,
    experience: ?Experience = null,
    health: ?Health = null,
    hunger: ?Hunger = null,
    improvements: ?Improvements = null,
    initiative: ?Initiative = null,
    inventory: ?Inventory = null,
    ladder: ?Ladder = null,
    level_up: ?LevelUp = null,
    pile: ?Pile = null,
    poison: ?Poison = null,
    position: ?Position = null,
    potion: ?Potion = null,
    price: ?Price = null,
    regeneration: ?Regeneration = null,
    shop: ?Shop = null,
    skills: ?Skills = null,
    source_of_light: ?SourceOfLight = null,
    speed: ?Speed = null,
    sprite: ?Sprite, // must be provided for every entity
    state: ?EnemyState = null,
    stats: ?Stats = null,
    trap: ?Trap = null,
    wallet: ?Wallet = null,
    weapon: ?Weapon = null,

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
