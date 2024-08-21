const std = @import("std");
const ecs = @import("ecs");

pub usingnamespace @import("components.zig");

pub const AnyRuntime = @import("AnyRuntime.zig");
pub const Buttons = @import("Buttons.zig");

pub const Entity = ecs.Entity;
pub const Screen = @import("Screen.zig");
pub const Dungeon = @import("BspDungeon.zig").BspDungeon(WHOLE_DUNG_ROWS, WHOLE_DUNG_COLS);
// pub const Dungeon = @import("BspDungeon.zig").BspDungeon(DISPLPAY_ROWS, DISPLPAY_COLS);

pub const GameSession = @import("GameSession.zig");
pub const PlayMode = @import("PlayMode.zig");
pub const PauseMode = @import("PauseMode.zig");

/// The maximum rows count in the whole dungeon
pub const WHOLE_DUNG_ROWS: u8 = 40;
/// The maximum columns count in the whole dungeon
pub const WHOLE_DUNG_COLS: u8 = 100;

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

pub const DISPLAY_ROWS = DISPLAY_HEIGHT / SPRITE_HEIGHT - 1;
pub const DISPLAY_COLS = DISPLAY_WIDHT / SPRITE_WIDTH - 1;

pub const DOUBLE_PUSH_DELAY_MS = 250;
pub const HOLD_DELAY_MS = 500;

test {
    std.testing.refAllDecls(@This());
}
