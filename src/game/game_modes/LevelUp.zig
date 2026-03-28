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

const SKILLS_AREA_REGION: p.Region = .{
    .top_left = .{ .row = 4, .col = 2 },
    .rows = g.DISPLAY_ROWS - 2 - 4,
    .cols = g.DISPLAY_COLS - 2,
};

const Self = @This();

session: *g.GameSession,
/// Used to revert everything in case of canceling
original_levels: c.LevelUp,
original_skills: c.Skills,
/// The current level of the player
current_level: u4,
levels: *c.LevelUp,
current_skills: *c.Skills,
options: w.OptionsArea(g.meta.Skill),
remaining_points: u4,

pub fn init(session: *g.GameSession) !Self {
    log.debug("Init LevelUp mode", .{});
    const current_level = session.registry.getUnsafe(session.player, c.Experience).level;
    const levels = session.registry.getUnsafe(session.player, c.LevelUp);
    const skills = session.registry.getUnsafe(session.player, c.Skills);
    var options: w.OptionsArea(g.meta.Skill) = .init(session, .left);
    for (std.enums.values(g.meta.Skill)) |skill| {
        const option = try options.addEmptyOption(
            session.arena.allocator(),
            skill,
        );
        option.label_len = SKILLS_AREA_REGION.cols;
        _ = try std.fmt.bufPrint(
            &option.label_buffer,
            "{s}",
            .{descriptions.castByNameAndGet(skill).name},
        );
        option.label_buffer[option.label_len - 3] = '0' + @as(u8, @intCast(skills.values.get(skill)));
    }
    return .{
        .session = session,
        .levels = levels,
        .original_levels = levels.*,
        .current_level = current_level,
        .original_skills = skills.*,
        .current_skills = skills,
        .options = options,
        .remaining_points = current_level - levels.last_handled_level,
    };
}

pub fn deinit(self: *Self) void {
    self.options.deinit(self.session.arena.allocator());
}

pub fn tick(self: *Self) !void {
    // Nothing should happened until the player push a button
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.game_button) {
            .up, .down => _ = try self.options.handleButton(btn),
            .left, .right => {
                const option = self.options.selectedOption();
                if (btn.game_button == .right)
                    self.increaseSkill(option.item)
                else
                    self.decriseSkill(option.item);

                const new_value = self.current_skills.values.get(option.item);
                option.label_buffer[option.label_len - 3] = '0' + @as(u8, @intCast(new_value));
            },
            .b => {
                // Canceling. Revert any changes.
                self.levels.* = self.original_levels;
                self.current_skills.* = self.original_skills;
                try self.session.continuePlay(null, null);
            },
            .a => {
                // All done. Continue playing.
                try self.session.continuePlay(null, null);
            },
        }
        try self.draw(self.session.render);
    }
}

fn showDescription(self: *Self, description: *const g.descriptions.Description) !void {
    var area: w.TextArea = .empty;
    for (description.description) |descr_line| {
        const line = try area.addEmptyLine(self.session.arena.allocator());
        _ = try std.fmt.bufPrint(line, "{s}", .{descr_line});
    }
    var window: w.ModalWindow(w.TextArea) = .defaultModalWindow(area);
    window.title_len = (try std.fmt.bufPrint(&window.title_buffer, "{s}", .{description.name})).len;
    self.description = window;
}

fn increaseSkill(self: *@This(), skill: g.meta.Skill) void {
    if (self.remaining_points > 0) {
        const new_value = self.current_skills.values.get(skill) + 1;
        self.current_skills.values.set(skill, new_value);
        self.remaining_points -= 1;
        self.levels.last_handled_level += 1;
    }
}
fn decriseSkill(self: *@This(), skill: g.meta.Skill) void {
    const original_value = self.original_skills.values.get(skill);
    const current_value = self.current_skills.values.get(skill);
    if (current_value > original_value) {
        const new_value = current_value - 1;
        self.current_skills.values.set(skill, new_value);
        self.remaining_points += 1;
        self.levels.last_handled_level -= 1;
    }
}

pub fn draw(self: Self, render: g.Render) !void {
    try render.clearDisplay();
    const title_point = p.Point.init(1, 1);
    try render.drawHorizontalLine('═', title_point.movedTo(.down), g.DISPLAY_COLS);
    try render.drawHorizontalLine('═', p.Point.init(g.DISPLAY_ROWS - 1, 1), g.DISPLAY_COLS);
    var buf: [g.DISPLAY_COLS]u8 = undefined;
    const title: []const u8 = if (self.levels.last_handled_level < self.current_level)
        try std.fmt.bufPrint(&buf, "New level: {d}", .{self.levels.last_handled_level + 1})
    else
        "All done!";
    try render.drawTextWithAlign(
        g.DISPLAY_COLS,
        title,
        title_point,
        .normal,
        .center,
    );
    try self.options.draw(render, SKILLS_AREA_REGION, 0);
    try render.drawInfo(
        try std.fmt.bufPrint(&buf, "{d} points remain", .{self.remaining_points}),
    );
    try render.drawLeftButton("Cancel", false);
    try render.drawRightButton("Apply", false);
}
