const std = @import("std");

pub const actions = @import("actions.zig");
pub const codepoints = @import("codepoints.zig");
pub const components = @import("components.zig");
pub const descriptions = @import("descriptions/descriptions_pkg.zig");
pub const dungeon = @import("dungeon/dungeon_pkg.zig");
pub const ecs = @import("ecs/ecs_pkg.zig");
pub const entities = @import("entities/entities_pkg.zig");
pub const events = @import("events.zig");
pub const meta = @import("meta.zig");
pub const notifications = @import("notifications.zig");
pub const persistance = @import("persistance.zig");
pub const primitives = @import("primitives.zig");
pub const systems = @import("systems/systems_pkg.zig");
pub const utils = @import("utils/utils_pkg.zig");
pub const visibility = @import("visibility.zig");
pub const windows = @import("windows/windows_pkg.zig");

pub const Action = actions.Action;
pub const AI = @import("AI.zig");
pub const Button = @import("Button.zig");
pub const CharacterBuilder = @import("CharacterBuilder.zig");
pub const Cheat = @import("cheats.zig").Cheat;
pub const Codepoint = u21;
pub const Color = enum {
    black,
    blue,
    brown,
    cyan,
    green,
    orange,
    pink,
    purple,
    red,
    teal,
    white,
    yellow,
};
pub const Description = @import("Description.zig");
pub const DrawingMode = Runtime.DrawingMode;
pub const Enemy = std.meta.FieldEnum(@import("descriptions/Enemies.zig"));
pub const Entity = ecs.Entity;
pub const Game = @import("Game.zig");
pub const GameSession = @import("GameSession.zig");
pub const Journal = @import("Journal.zig");
pub const Level = @import("Level.zig");
pub const MovePoints = @import("actions.zig").MovePoints;
pub const PlayerArchetype = std.meta.FieldEnum(@import("descriptions/Archetypes.zig"));
pub const Registry = ecs.Registry(components.Components);
pub const Render = @import("Render.zig");
pub const Runtime = @import("Runtime.zig");
pub const TextAlign = Runtime.TextAlign;
pub const Viewport = @import("Viewport.zig");

pub const GameStateArena = std.heap.ArenaAllocator;
pub const SessionModeArena = std.heap.ArenaAllocator;
pub const LevelArena = std.heap.ArenaAllocator;

/// Errors raised while validating or converting UTF-8 codepoints.
pub const Utf8Error = error{
    CodepointTooLarge,
    InvalidUtf8,
    TruncatedInput,
    Utf8CannotEncodeSurrogateHalf,
    Utf8CodepointTooLarge,
    Utf8EncodesSurrogateHalf,
    Utf8ExpectedContinuation,
    Utf8InvalidStartByte,
    Utf8OverlongEncoding,
};

/// Errors returned by allocator operations, primarily `OutOfMemory`.
pub const AllocatorError = std.mem.Allocator.Error;

/// Indicates that a dungeon could not be generated for the requested seed.
/// Algorithm-specific generation errors are translated to this error at the
/// public dungeon-generation boundary.
pub const DungeonGenerationError = error{DungeonGenerationFailed};

/// Operational errors that can occur across game systems, including runtime,
/// persistence, formatting, allocation, and dungeon generation failures.
pub const SystemError = Runtime.Error || persistance.Error || Utf8Error ||
    DungeonGenerationError ||
    AllocatorError ||
    std.Io.Reader.Error ||
    std.Io.Writer.Error ||
    std.fmt.BufPrintError;

/// Control-flow signal requesting that the game return to its main menu.
pub const GoToMainMenuError = error{GoToMainMenu};

/// Control-flow signal indicating that the player has died and the game-over
/// flow should begin.
pub const GameOverError = error{GameOver};

/// Union of errors that may escape the top-level game flow. Use narrower sets
/// for functions that only need to expose a subset of these outcomes.
pub const AllErrors = SystemError || GameOverError || GoToMainMenuError;

pub const MAX_DEPTH = 9;

/// How many move points should spent player to increase a turns counter
pub const MOVE_POINTS_IN_TURN = 10;

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
