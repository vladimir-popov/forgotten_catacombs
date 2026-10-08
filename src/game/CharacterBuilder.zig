//! This is a mode to choose a character archetype and set up skills at the start of the game.
//! ```
//! Archetype Step:
//! Stats Step:
//! Skills Step:
//! Confirm Step:
//! ```
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const descriptions = g.components.Description.Preset;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.explore_level_mode);

const Self = @This();

archetype: g.meta.PlayerArchetype = .adventurer,
stats: c.Stats = undefined,
skills: c.Skills = .zeros,
health: c.Health = undefined,
wizard: w.wizard.WizardWindow(union {
    archetype: w.wizard.ChooseArchetypeStep(Self),
    stats: w.wizard.ManageStatsStep(Self),
    skills: w.wizard.ManageSkillsStep(Self),
    confirm: w.wizard.ConfirmCharacterStep(Self),
}, Self) = undefined,

pub fn init(self: *Self, alloc: std.mem.Allocator) !void {
    self.* = .{};
    try self.wizard.init(alloc, self);
}

pub fn deinit(self: *Self) void {
    self.wizard.deinit();
}

pub fn statsRemainingPoints(self: *const Self) u2 {
    return if (self.archetype == .adventurer) 2 else 1;
}

pub fn skillsRemainingPoints(_: *const Self) u2 {
    return 2;
}
