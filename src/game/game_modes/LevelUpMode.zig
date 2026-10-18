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

const StatsAndSkillsWizard = w.wizard.WizardWindow(union {
    stats: w.wizard.ManageStatsStep(Self),
    skills: w.wizard.ManageSkillsStep(Self),
}, Self);

const OnlySkillsWizard = w.wizard.WizardWindow(union {
    skills: w.wizard.ManageSkillsStep(Self),
}, Self);

session: *g.GameSession,
/// Used to revert everything in case of canceling
original_experience: c.Experience,
original_stats: c.Stats,
original_skills: c.Skills,
/// The current level of the player
experience: *c.Experience,
stats: *c.Stats,
skills: *c.Skills,
health: *c.Health,
wizard: union(enum) { stats_and_skills: StatsAndSkillsWizard, only_skills: OnlySkillsWizard },

pub fn init(self: *Self, session: *g.GameSession) g.SystemError!void {
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
        .health = session.registry.getUnsafe(session.player, c.Health),
        .wizard = if (self.statsRemainingPoints() > 0)
            .{ .stats_and_skills = undefined }
        else
            .{ .only_skills = undefined },
    };
    switch (self.wizard) {
        .stats_and_skills => |*wz| try wz.init(session.mode_arena.allocator(), self),
        .only_skills => |*wz| try wz.init(session.mode_arena.allocator(), self),
    }
}

pub fn deinit(self: *Self) void {
    switch (self.wizard) {
        .stats_and_skills => |*wz| wz.deinit(),
        .only_skills => |*wz| wz.deinit(),
    }
}

// Keep mode-specific temporaries out of GameSession.tick's shared stack frame
// to reduce stack usage in other modes on Playdate.
pub noinline fn tick(self: *Self) g.AllErrors!void {
    // Nothing should happened until the player push a button
    if (try self.session.runtime.readPushedButtons()) |btn| {
        const result = switch (self.wizard) {
            .stats_and_skills => |*wz| try wz.handleButton(btn),
            .only_skills => |*wz| try wz.handleButton(btn),
        };
        if (result == .close_window) {
            if (btn.game_button == .b) {
                // Canceling. Revert any changes.
                self.experience.* = self.original_experience;
                self.stats.* = self.original_stats;
                self.skills.* = self.original_skills;
                try self.session.continuePlay(null, null);
                return;
            }
            if (btn.game_button == .a) {
                // All done. Continue playing.
                self.experience.last_handled_level = self.experience.level;
                self.health.max = g.meta.initialHealth(self.stats.get(.constitution)).max;
                try self.session.continuePlay(null, null);
                return;
            }
        }
        try self.draw(self.session.render);
    }
}

pub fn draw(self: *Self, render: g.Render) g.SystemError!void {
    switch (self.wizard) {
        .stats_and_skills => |*wz| try wz.draw(render),
        .only_skills => |*wz| try wz.draw(render),
    }
}

pub fn statsRemainingPoints(self: *const Self) u4 {
    const first_unhandled_level = self.experience.last_handled_level + 1;
    if (first_unhandled_level > self.experience.level) return 0;

    // Stat points are awarded on levels 3, 6, 9, ... .
    return self.experience.level / 3 - (first_unhandled_level - 1) / 3;
}

pub fn skillsRemainingPoints(self: *const Self) u4 {
    return self.experience.level - self.experience.last_handled_level;
}
