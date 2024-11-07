const std = @import("std");

pub const components = @import("components.zig");
pub const ecs = @import("ecs.zig");
pub const entities = @import("entities.zig");
pub const events = @import("events.zig");
pub const primitives = @import("primitives.zig");
pub const render = @import("Render.zig");

pub const Entity = ecs.Entity;
pub const Runtime = @import("Runtime.zig");
pub const Button = @import("Button.zig");
pub const Cheat = @import("cheats.zig").Cheat;
pub const Dungeon = @import("dungeon/Dungeon.zig");
pub const Game = @import("Game.zig");
pub const GameSession = @import("GameSession.zig");
pub const Level = @import("Level.zig");
pub const LevelMap = @import("LevelMap.zig");
pub const Render = render.Render(DISPLAY_ROWS, DISPLAY_COLS);
pub const Viewport = @import("Viewport.zig");

pub const RENDER_DELAY_MS = 150;

// Playdate display resolution px:
pub const DISPLAY_HEIGHT = 240;
pub const DISPLAY_WIDHT = 400;

// The size of the font to draw sprites in pixels:
pub const SPRITE_HEIGHT = 20;
pub const SPRITE_WIDTH = 10;

// The size of the font for text in pixels:
pub const FONT_HEIGHT = 16;
pub const FONT_WIDTH = 8;

/// 12
pub const DISPLAY_ROWS = DISPLAY_HEIGHT / SPRITE_HEIGHT;
/// 40
pub const DISPLAY_COLS = DISPLAY_WIDHT / SPRITE_WIDTH;

pub const DOUBLE_PUSH_DELAY_MS = 250;
pub const HOLD_DELAY_MS = 500;

test {
    std.testing.refAllDecls(@This());
}
