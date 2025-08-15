const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const u = g.utils;

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
    preset: g.descriptions.Presets.Keys,

    pub fn name(self: *const Description) []const u8 {
        return g.descriptions.Presets.get(self.preset).name;
    }

    pub fn description(self: *const Description) []const []const u8 {
        return g.descriptions.Presets.get(self.preset).description;
    }
};

pub const Animation = struct {
    pub const FramesPresets = u.Preset(struct {
        empty: []const g.Codepoint = &[_]g.Codepoint{},
        get_angry: []const g.Codepoint = &[_]g.Codepoint{ 0, '!', 0, '!', 0, '!' },
        go_sleep: []const g.Codepoint = &[_]g.Codepoint{ 0, 'z', 0, 'z', 0, 'z' },
        hit: []const g.Codepoint = &[_]g.Codepoint{ 0, '×', 0 },
        relax: []const g.Codepoint = &[_]g.Codepoint{ 0, '?', 0, '?', 0, '?' },
        wait: []const g.Codepoint = &[_]g.Codepoint{ 'z', 'Z', 'z', 'Z' },
    });

    preset: FramesPresets.Keys,
    current_frame: u8 = 0,
    previous_render_time: c_uint = 0,
    /// true means that input should not be handled until all frames of this animation will be played.
    is_blocked: bool = false,

    pub fn frame(self: *Animation, now: u32) ?g.Codepoint {
        const frames = FramesPresets.get(self.preset);
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

/// Faded impact of different effects. This is not a component, because
/// only one instance of the component with same type can be defined for an entity.
/// Instead, the `Impacts` component exists.
pub const Effect = union(enum) {
    pub const Tag = std.meta.Tag(Effect);

    pub const Impact = struct {
        /// The power of the effect that should be applied
        power: u8,
        /// The value to decrease the power of the effect after every applying
        decrease: u8,

        pub fn sumWith(this: Impact, impact: ?Impact) Impact {
            return if (impact) |other|
                .{ .power = @max(this.power, other.power), .decrease = @min(this.decrease, other.decrease) }
            else
                this;
        }

        pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("{d}/{d}", .{ self.power, self.decrease });
        }
    };

    burning: Impact,
    corrosion: Impact,
    healing: Impact,
    poisoning: Impact,

    pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .burning, .corrosion, .healing, .poisoning => |impact| {
                try writer.print("{s} {any}", .{ @tagName(self), impact });
            },
        }
    }
};

// this is not a component
pub const DamageType = enum { cutting, blunt, thrusting, poison, fire, acid };

pub const Weapon = struct {
    damage_type: DamageType,
    damage_min: u8,
    damage_max: u8,
    effects: std.SegmentedList(Effect, 1) = .{},

    pub fn cutting(from: u8, to: u8) Weapon {
        return .{ .damage_min = from, .damage_max = to, .damage_type = .cutting };
    }

    pub fn blunt(from: u8, to: u8) Weapon {
        return .{ .damage_min = from, .damage_max = to, .damage_type = .blunt };
    }

    pub fn thrusting(from: u8, to: u8) Weapon {
        return .{ .damage_min = from, .damage_max = to, .damage_type = .thrusting };
    }

    pub fn withEffect(damage_type: DamageType, from: u8, to: u8, effect: Effect) Weapon {
        return .{
            .damage_min = from,
            .damage_max = to,
            .damage_type = damage_type,
            .effects = .{ .prealloc_segment = .{effect}, .len = 1 },
        };
    }

    /// - `writer` - as example: `*persistance.Writer(Runtime.FileWriter.Writer)`
    pub fn save(self: Weapon, writer: anytype) !void {
        try writer.beginObject();
        try writer.writeStringKey("damage_type");
        try writer.write(self.damage_type);
        try writer.writeStringKey("damage_min");
        try writer.write(self.damage_min);
        try writer.writeStringKey("damage_max");
        try writer.write(self.damage_max);
        try writer.writeStringKey("effects");
        try writer.beginCollection();
        var itr = self.effects.constIterator(0);
        while (itr.next()) |effect| {
            try writer.write(effect);
        }
        try writer.endCollection();
        try writer.endObject();
    }

    /// - `reader` - as example: `*persistance.Reader(Runtime.FileReader.Reader)`
    pub fn load(reader: anytype) !Weapon {
        var weapon: Weapon = undefined;
        weapon.effects = .{};
        try reader.beginObject();
        _ = try reader.readKeyAsString();
        weapon.damage_type = try reader.read(DamageType);
        _ = try reader.readKeyAsString();
        weapon.damage_min = try reader.read(u8);
        _ = try reader.readKeyAsString();
        weapon.damage_max = try reader.read(u8);
        _ = try reader.readKeyAsString();
        try reader.beginCollection();
        while (!try reader.isCollectionEnd()) {
            try weapon.effects.append(reader.registry.allocator(), try reader.read(Effect));
        }
        try reader.endCollection();
        try reader.endObject();
        return weapon;
    }
};

/// A set of faded effects. An effect of the any type can be applied to an entity only once.
pub const Impacts = struct {
    pub const Type = std.meta.FieldEnum(Impacts);

    burning: ?Effect.Impact = null,
    corrosion: ?Effect.Impact = null,
    healing: ?Effect.Impact = null,
    poisoning: ?Effect.Impact = null,

    pub fn isNothing(self: Impacts) bool {
        return self.burning == null and self.corrosion == null and self.healing == null and self.poisoning == null;
    }

    pub fn add(self: *Impacts, effect: *const Effect) void {
        switch (effect.*) {
            .burning => |impact| {
                self.burning = impact.sumWith(self.burning);
            },
            .corrosion => |impact| {
                self.corrosion = impact.sumWith(self.corrosion);
            },
            .healing => |impact| {
                self.healing = impact.sumWith(self.healing);
            },
            .poisoning => |impact| {
                self.poisoning = impact.sumWith(self.poisoning);
            },
        }
    }

    pub fn toDamageType(impact_type: Type) ?DamageType {
        return switch (impact_type) {
            .burning => .fire,
            .corrosion => .acid,
            .poisoning => .poison,
            else => null,
        };
    }
};

pub const Potion = struct {
    effect: Effect,

    pub fn healing(value: u8) Potion {
        return .{ .effect = .{ .healing = .{ .power = value, .decrease = value } } };
    }
};

pub const Regeneration = struct {
    /// An amount of health point to restore (or decrease in case of poisoning)
    hp: i8,
    /// A number of move points on each hp should be recovered
    mp: u8,
};

pub const Nutritions = struct {
    calories: u8,
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

pub const Weight = struct {
    value: u8,
};

pub const Components = struct {
    animation: ?Animation = null,
    description: ?Description, // must be provided for every entity
    door: ?Door = null,
    equipment: ?Equipment = null,
    health: ?Health = null,
    impacts: ?Impacts = null,
    initiative: ?Initiative = null,
    inventory: ?Inventory = null,
    ladder: ?Ladder = null,
    pile: ?Pile = null,
    position: ?Position = null,
    potion: ?Potion = null,
    price: ?Price = null,
    shop: ?Shop = null,
    source_of_light: ?SourceOfLight = null,
    speed: ?Speed = null,
    sprite: ?Sprite, // must be provided for every entity
    state: ?EnemyState = null,
    wallet: ?Wallet = null,
    weapon: ?Weapon = null,
    weight: ?Weight = null,
};
