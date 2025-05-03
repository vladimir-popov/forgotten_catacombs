const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const Position = struct {
    point: p.Point,
};

pub const Door = struct { state: enum { opened, closed } };

/// Describes how and where something should look.
pub const Sprite = struct {
    codepoint: g.Codepoint,
    /// The sprite with bigger order should be rendered over the sprite with lower
    z_order: g.ZOrder,
};

pub const Description = struct {
    name: []const u8,
    description: []const u8 = "",
};

pub const Animation = struct {
    pub const FramesPresets = struct {
        pub const hit: [3]g.Codepoint = [_]g.Codepoint{ 0, '×', 0 };
        pub const miss: [1]g.Codepoint = [_]g.Codepoint{'.'};
        pub const go_sleep: [6]g.Codepoint = [_]g.Codepoint{ 0, 'z', 'z', 0, 'z', 'z' };
        pub const relax: [6]g.Codepoint = [_]g.Codepoint{ 0, '?', '?', 0, '?', '?' };
        pub const get_angry: [6]g.Codepoint = [_]g.Codepoint{ 0, '!', '!', 0, '!', '!' };
    };

    /// Frames of the animation. One frame per render circle will be shown.
    frames: []const g.Codepoint,
    current_frame: u8 = 0,
    previous_render_time: c_uint = 0,
    lag: u32 = 0,

    pub fn frame(self: *Animation, now: u32) ?g.Codepoint {
        self.lag += now - self.previous_render_time;
        self.previous_render_time = now;
        if (self.lag > g.RENDER_DELAY_MS) {
            self.lag = 0;
            self.current_frame += 1;
        }
        return if (self.current_frame <= self.frames.len) self.frames[self.current_frame - 1] else null;
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
    move_points: u8 = 10,
};

pub const Weapon = struct {
    max_damage: u8,

    pub inline fn generateDamage(self: Weapon, rand: std.Random) u8 {
        return rand.uintLessThan(u8, self.max_damage) + 1;
    }
};

pub const Initiative = struct {
    move_points: g.MovePoints = 0,
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
    description: ?Description = null,
    door: ?Door = null,
    state: ?EnemyState = null,
    health: ?Health = null,
    initiative: ?Initiative = null,
    ladder: ?Ladder = null,
    position: ?Position = null,
    source_of_light: ?SourceOfLight = null,
    speed: ?Speed = null,
    sprite: ?Sprite = null,
    weapon: ?Weapon = null,
};
