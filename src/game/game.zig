const std = @import("std");
const ecs = @import("ecs");

pub usingnamespace @import("components.zig");

pub const AnyRuntime = @import("AnyRuntime.zig");
pub const Buttons = @import("Buttons.zig");

pub const Entity = ecs.Entity;
pub const Screen = @import("Screen.zig");
pub const Dungeon = @import("BspDungeon.zig").BspDungeon(TOTAL_DUNG_ROWS, TOTAL_DUNG_COLS);
// pub const Dungeon = @import("BspDungeon.zig").BspDungeon(DISPLPAY_ROWS, DISPLPAY_COLS);

pub const GameSession = @import("GameSession.zig");
pub const PlayMode = @import("PlayMode.zig");
pub const PauseMode = @import("PauseMode.zig");

pub const RENDER_DELAY_MS = 150;

// Playdate display resolution px:
pub const DISPLPAY_HEGHT = 240;
pub const DISPLPAY_WIGHT = 400;

// Font size px:
pub const FONT_HEIGHT = 20;
pub const FONT_WIDTH = 10;

pub const DISPLPAY_ROWS = DISPLPAY_HEGHT / FONT_HEIGHT - 1;
pub const DISPLPAY_COLS = DISPLPAY_WIGHT / FONT_WIDTH - 1;

// The size of the zone with stats:
pub const STATS_ROWS = DISPLPAY_ROWS;
pub const STATS_COLS = 8;

/// The maximum rows count in the dungeon
pub const TOTAL_DUNG_ROWS: u8 = 40;
/// The maximum columns count in the dungeon
pub const TOTAL_DUNG_COLS: u8 = 100;

/// The rows count to display
pub const DISPLAY_DUNG_ROWS = STATS_ROWS;
/// The rows count to display
pub const DISPLAY_DUNG_COLS = DISPLPAY_COLS - STATS_COLS;

test {
    std.testing.refAllDecls(@This());
}
