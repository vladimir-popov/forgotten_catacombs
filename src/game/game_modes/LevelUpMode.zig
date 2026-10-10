//! ```
//! ╔════════════════════════════════════════╗
//! ║            New level {d}               ║
//! ║════════════════════════════════════════║
//! ║ ┌                                      ║
//! ║  Weapon Mastery                      0 ║
//! ║  Mechanics                           0 ║
//! ║  Stealth                             0 ║
//! ║  Echo of knowledge                   0 ║
//! ║                                       ┘║
//! ║                                        ║
//! ║                                        ║
//! ║════════════════════════════════════════║
//! ║  {d} points remain   Cancel  Describe  ║
//! ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;
const descriptions = g.components.Description.Preset;

const log = std.log.scoped(.level_up_mode);

const Self = @This();

session: *g.GameSession,
/// Used to revert everything in case of canceling
original_experience: c.Experience,
original_stats: c.Stats,
original_skills: c.Skills,
/// The current level of the player
experience: *c.Experience,
stats: *c.Stats,
skills: *c.Skills,
initial_step: usize,
wizard: w.wizard.WizardWindow(union {
    stats: w.wizard.ManageStatsStep(Self),
    skills: w.wizard.ManageSkillsStep(Self),
}, Self),

pub fn init(self: *Self, session: *g.GameSession) !void {
    log.debug("Init LevelUp mode", .{});
    const exp = session.registry.getUnsafe(session.player, c.Experience);
    const stats = session.registry.getUnsafe(session.player, c.Stats);
    const skills = session.registry.getUnsafe(session.player, c.Skills);
    self.* = .{
        .session = session,
        .original_experience = exp.*,
        .experience = exp,
        .original_stats = stats.*,
        .original_skills = skills.*,
        .stats = stats,
        .skills = skills,
        .initial_step = if (self.statsRemainingPoints() > 0) 0 else 1,
        .wizard = undefined,
    };
    try self.wizard.init(session.mode_arena.allocator(), self);
    if (self.initial_step == 1) {
        try self.wizard.switchToStep(1);
    }
}

pub fn deinit(self: *Self) void {
    self.wizard.deinit();
}

pub fn statsRemainingPoints(self: *const Self) u4 {
    const first_unhandled_level = self.experience.last_handled_level + 1;
    const actual_level = self.experience.actualLevel();
    if (first_unhandled_level > actual_level) return 0;

    // Stat points are awarded on levels 3, 6, 9, ... .
    return actual_level / 3 - (first_unhandled_level - 1) / 3;
}

pub fn skillsRemainingPoints(self: *const Self) u4 {
    return 2 * (self.experience.actualLevel() - self.experience.last_handled_level);
}

pub fn tick(self: *Self) !void {
    // Nothing should happened until the player push a button
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.game_button) {
            .b => if (self.wizard.current_step == self.initial_step) {
                // Canceling. Revert any changes.
                self.experience.* = self.original_experience;
                self.stats.* = self.original_stats;
                self.skills.* = self.original_skills;
                try self.session.continuePlay(null, null);
            },
            else => if (try self.wizard.handleButton(btn) == .close_window) {
                // All done. Continue playing.
                self.experience.level = self.experience.actualLevel();
                try self.session.continuePlay(null, null);
            },
        }
        try self.draw(self.session.render);
    }
}

pub fn draw(self: *Self, render: g.Render) !void {
    try self.wizard.draw(render);
}
