const std = @import("std");

pub const actions = @import("actions.zig");
pub const codepoints = @import("codepoints.zig");
pub const components = @import("components.zig");
pub const descriptions = @import("descriptions.zig");
pub const dungeon = @import("dungeon/dungeon_pkg.zig");
pub const ecs = @import("ecs/ecs_pkg.zig");
pub const entities = @import("entities/entities.zig");
pub const events = @import("events.zig");
pub const meta = @import("meta.zig");
pub const persistance = @import("persistance.zig");
pub const primitives = @import("primitives.zig");
pub const utils = @import("utils/utils_pkg.zig");
pub const visibility = @import("visibility_strategies.zig");
pub const windows = @import("windows/windows_pkg.zig");

pub const Action = actions.Action;
pub const AI = @import("AI.zig");
pub const Button = @import("Button.zig");
pub const CharacterBuilder = @import("CharacterBuilder.zig");
pub const Cheat = @import("cheats.zig").Cheat;
pub const Codepoint = u21;
pub const Color = enum { red, green, blue, black, white };
pub const DrawingMode = Runtime.DrawingMode;
pub const Entity = ecs.Entity;
pub const Game = @import("Game.zig");
pub const GameSession = @import("GameSession.zig");
pub const Journal = @import("Journal.zig");
pub const Level = @import("Level.zig");
pub const MovePoints = @import("actions.zig").MovePoints;
pub const Registry = ecs.Registry(components.Components);
pub const Render = @import("Render.zig");
pub const Runtime = @import("Runtime.zig");
pub const TextAlign = Runtime.TextAlign;
pub const Viewport = @import("Viewport.zig");

pub const presets = struct {
    pub const Descriptions = utils.Preset(descriptions.Description, descriptions);
    pub const Items = utils.Preset(components.Components, entities.Items);
};

/// How many move points should spent player to increase a turns counter
pub const MOVE_POINTS_IN_TURN = 10;

/// A delay between frames of animation
pub const RENDER_DELAY_MS = 200;

// Playdate display resolution px:
pub const DISPLAY_HEIGHT = 240;
pub const DISPLAY_WIDHT = 400;

// The size of the font to draw sprites in pixels:
pub const SPRITE_HEIGHT = 20;
pub const SPRITE_WIDTH = 10;

/// 12
pub const DISPLAY_ROWS = DISPLAY_HEIGHT / SPRITE_HEIGHT;
/// 40
pub const DISPLAY_COLS = DISPLAY_WIDHT / SPRITE_WIDTH;

/// 36
pub const DUNGEON_ROWS = DISPLAY_ROWS * 3;
/// 120
pub const DUNGEON_COLS = DISPLAY_COLS * 3;

pub const DUNGEON_REGION: primitives.Region = .{
    .top_left = .{ .row = 1, .col = 1 },
    .rows = DUNGEON_ROWS,
    .cols = DUNGEON_COLS,
};

test {
    std.testing.refAllDecls(@This());
}
