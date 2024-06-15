const std = @import("std");
const ecs = @import("ecs");

pub usingnamespace @import("components.zig");

pub const AnyRuntime = @import("AnyRuntime.zig");

pub const Entity = ecs.Entity;
pub const Screen = @import("Screen.zig");
pub const Dungeon = @import("BspDungeon.zig").BspDungeon(TOTAL_ROWS, TOTAL_COLS);

pub const InputSystem = @import("InputSystem.zig");
pub const RenderSystem = @import("RenderSystem.zig");
pub const MovementSystem = @import("MovementSystem.zig");

pub const GameSession = @import("GameSession.zig");

// Playdate resolution: h:240 × w:400 pixels
// we expect at least 4x4 sprite to render the whole level map
// and 16x8 to render the game in play mode

/// The maximum rows count in the dungeon
pub const TOTAL_ROWS: u8 = 40;
/// The maximum columns count in the dungeon
pub const TOTAL_COLS: u8 = 100;

/// The rows count to display
pub const DISPLAY_ROWS: u8 = 15;
/// The rows count to display
pub const DISPLAY_COLS: u8 = 40;

const ROWS_PAD = 3;
const COLS_PAD = 7;
