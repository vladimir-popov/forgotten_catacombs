const std = @import("std");

pub const components = @import("components.zig");
pub const dungeon = @import("dungeon/dungeon_pkg.zig");
pub const ecs = @import("ecs.zig");
pub const entities = @import("entities.zig");
pub const events = @import("events.zig");
pub const primitives = @import("primitives.zig");
pub const visibility = @import("visibility_strategies.zig");

pub const Action = ActionSystem.Action;
pub const ActionSystem = @import("ActionSystem.zig");
pub const AI = @import("AI.zig");
pub const Button = @import("Button.zig");
pub const Cheat = @import("cheats.zig").Cheat;
pub const Codepoint = u21;
pub const DijkstraMap = @import("DijkstraMap.zig");
pub const Entity = ecs.Entity;
pub const Game = @import("Game.zig");
pub const GameSession = @import("GameSession.zig");
pub const Level = @import("Level.zig");
pub const LevelMap = @import("LevelMap.zig");
pub const Levels = @import("Levels.zig");
pub const MovePoints = ActionSystem.MovePoints;
pub const Render = @import("Render.zig");
pub const Runtime = @import("Runtime.zig");
pub const Viewport = @import("Viewport.zig");
pub const ZOrder = u3;

pub const RENDER_DELAY_MS = 150;

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

pub const DOUBLE_PUSH_DELAY_MS = 250;
pub const HOLD_DELAY_MS = 500;

test {
    std.testing.refAllDecls(@This());
}
