//! This is a mode to choose a character archetype and set up skills at the start of the game.
//! ```
//! Archetype Step:
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

const MAX_REMAINING_POINTS = 2;

const ARCHETYPE_AREA_REGION: p.Region = .{
    .top_left = .{ .row = 4, .col = 12 },
    .rows = g.DISPLAY_ROWS - 2 - 4,
    .cols = g.DISPLAY_COLS - 24,
};
const SKILLS_AREA_REGION: p.Region = .{
    .top_left = .{ .row = 4, .col = 2 },
    .rows = g.DISPLAY_ROWS - 2 - 4,
    .cols = g.DISPLAY_COLS - 2,
};
const CONFIRM_AREA_REGION: p.Region = .{
    .top_left = .{ .row = 3, .col = 2 },
    .rows = g.DISPLAY_ROWS - 2 - 2,
    .cols = g.DISPLAY_COLS - 1,
};

/// A steps to setup the character
const BuildingStep = union(enum) {
    /// ```
    /// ╔════════════════════════════════════════╗
    /// ║         Choose your archetype:         ║
    /// ║════════════════════════════════════════║
    /// ║             ┌                          ║
    /// ║               Adventurer               ║
    /// ║              Archeologist              ║
    /// ║                 Vandal                 ║
    /// ║                 Rogue                  ║
    /// ║                          ┘             ║
    /// ║                                        ║
    /// ║                                        ║
    /// ║════════════════════════════════════════║
    /// ║                       Describe  Choose ║
    /// ╚════════════════════════════════════════╝
    /// ```
    archetype: w.OptionsArea(g.meta.PlayerArchetype),
    /// ```
    /// ╔════════════════════════════════════════╗
    /// ║                 Skill:                 ║
    /// ║════════════════════════════════════════║
    /// ║ ┌                                      ║
    /// ║  Weapon Mastery                      0 ║
    /// ║  Mechanics                           0 ║
    /// ║  Stealth                             0 ║
    /// ║  Echo of knowledge                   0 ║
    /// ║                                       ┘║
    /// ║                                        ║
    /// ║                                        ║
    /// ║════════════════════════════════════════║
    /// ║    2 points remain    Back   Describe  ║
    /// ╚════════════════════════════════════════╝
    /// ```
    skills: struct {
        stats: c.Stats,
        skills: c.Skills,
        remaining_points: u2,
        options: w.OptionsArea(g.meta.Skill),

        fn deinit(self: *@This()) void {
            self.options.deinit();
        }

        fn selectedSkill(self: @This()) g.meta.Skill {
            return self.options.selectedItem();
        }
        fn increaseSkill(self: *@This(), skill: g.meta.Skill) void {
            if (self.remaining_points > 0) {
                const new_value = self.skills.values.get(skill) + 1;
                self.skills.values.set(skill, new_value);
                self.remaining_points -= 1;
            }
        }
        fn decriseSkill(self: *@This(), skill: g.meta.Skill) void {
            if (self.remaining_points < 2) {
                const new_value = self.skills.values.get(skill) - 1;
                self.skills.values.set(skill, new_value);
                self.remaining_points += 1;
            }
        }
    },
    /// ```
    /// ╔════════════════════════════════════════╗
    /// ║       Start with this character?       ║
    /// ║  ┌                                     ║
    /// ║   Level: {d}                          ▒║
    /// ║   Experience: {d}/{d}                 ░║
    /// ║                                       ░║
    /// ║   Health: 30/30                       ░║
    /// ║                                       ░║
    /// ║   Skills:                             ░║
    /// ║     Weapon Mastery:     2             ░║
    /// ║     Mechanics           0             ░║
    /// ║════════════════════════════════════════║
    /// ║                       Back    Play     ║
    /// ╚════════════════════════════════════════╝
    /// ```
    confirm: struct {
        stats: c.Stats,
        skills: c.Skills,
        health: c.Health,
        description: w.ScrollableArea(w.TextArea),

        fn init(description: w.TextArea, stats: c.Stats, skills: c.Skills, health: c.Health) @This() {
            return .{
                .description = .{ .content = description, .region = CONFIRM_AREA_REGION },
                .stats = stats,
                .skills = skills,
                .health = health,
            };
        }

        fn deinit(self: *@This()) void {
            self.description.content.deinit();
        }
    },
};

arena: *g.GameStateArena,
step: BuildingStep,
// a popup window with description of a selected item (archetype, stat or skill)
description: ?w.Window,

pub fn init(self: *Self, arena: *g.GameStateArena) !void {
    self.arena = arena;
    self.description = null;
    try self.initArchetypeStep();
}

fn initArchetypeStep(self: *Self) !void {
    const arena_alloc = self.arena.allocator();
    self.step = .{ .archetype = w.OptionsArea(g.meta.PlayerArchetype).initEmpty(arena_alloc, self, .center) };
    for (std.enums.values(g.meta.PlayerArchetype)) |archetype| {
        const option = try self.step.archetype.addEmptyOption(
            archetype,
        );
        option.label_len = (try std.fmt.bufPrint(
            &option.label_buffer,
            "{s}",
            .{descriptions.castByNameAndGet(archetype).name},
        )).len;
    }
}

fn initSkillsStep(
    self: *Self,
    stats: c.Stats,
    skills: c.Skills,
    remaining_points: u2,
) !void {
    var options = w.OptionsArea(g.meta.Skill).initEmpty(self.arena.allocator(), self, .left);
    for (std.enums.values(g.meta.Skill)) |skill| {
        // the button handler is omitted, because we have a single point to handle buttons in this mode
        const option = try options.addEmptyOption(skill);
        option.label_len = SKILLS_AREA_REGION.cols;
        _ = try std.fmt.bufPrint(
            &option.label_buffer,
            "{s}",
            .{descriptions.castByNameAndGet(skill).name},
        );
        option.label_buffer[option.label_len - 3] = '0' + @as(u8, @intCast(skills.values.get(skill)));
    }
    self.step = .{ .skills = .{
        .stats = stats,
        .skills = skills,
        .remaining_points = remaining_points,
        .options = options,
    } };
}

fn initConfirmStep(self: *Self, stats: c.Stats, skills: c.Skills) !void {
    const health: c.Health = g.meta.initialHealth(stats.values.getAssertContains(.constitution));
    var text_area: w.TextArea = .initEmpty(self.arena.allocator());
    try g.Description.describeProgression(1, 0, &text_area);
    _ = try text_area.addEmptyLine();
    try g.Description.describeHealth(&health, &text_area);
    _ = try text_area.addEmptyLine();
    try g.Description.describeSkills(&skills, &text_area);
    _ = try text_area.addEmptyLine();
    try g.Description.describeStats(&stats, &text_area);
    self.step = .{ .confirm = .init(text_area, stats, skills, health) };
}

/// Handles the button and return chosen stats and skills on null if they are not selected yet.
pub fn handleButton(self: *Self, btn: g.Button, render: g.Render) anyerror!?struct { c.Stats, c.Skills, c.Health } {
    if (self.description) |*window| {
        if (try window.handleButton(btn) == .close_window) {
            try window.hide(render, .fill_region);
            window.deinit();
            self.description = null;
        }
    } else {
        switch (btn.game_button) {
            .up, .down => switch (self.step) {
                .archetype => |*archetype_step| {
                    _ = try archetype_step.handleButton(btn);
                },
                .skills => |*skill_step| {
                    _ = try skill_step.options.handleButton(btn);
                },
                .confirm => |*confirm_step| {
                    _ = try confirm_step.description.handleButton(btn);
                },
            },
            .left, .right => if (self.step == .skills) {
                const option = self.step.skills.options.selectedOption();
                if (btn.game_button == .right)
                    self.step.skills.increaseSkill(option.item)
                else
                    self.step.skills.decriseSkill(option.item);

                const new_value = self.step.skills.skills.values.get(option.item);
                option.label_buffer[option.label_len - 3] = '0' + @as(u8, @intCast(new_value));
            },
            // left button
            .b => switch (self.step) {
                .archetype => |archetype_step| {
                    const description = descriptions.castByNameAndGet(archetype_step.selectedItem());
                    try self.showDescription(description);
                },
                .skills => {
                    // back to archetype selection
                    self.step.skills.deinit();
                    try self.initArchetypeStep();
                },
                .confirm => |confirm_step| {
                    // back to skills selection
                    const stats = confirm_step.stats;
                    const skills = confirm_step.skills;
                    self.step.confirm.deinit();
                    try self.initSkillsStep(stats, skills, 0);
                },
            },
            // right button
            .a => {
                switch (self.step) {
                    .archetype => |archetype_step| {
                        try self.initSkillsStep(
                            g.meta.statsFromArchetype(archetype_step.selectedItem()),
                            .zeros,
                            MAX_REMAINING_POINTS,
                        );
                    },
                    .skills => |skills_step| {
                        if (skills_step.remaining_points > 0) {
                            const description = descriptions.castByNameAndGet(skills_step.selectedSkill());
                            try self.showDescription(description);
                        } else {
                            const stats = skills_step.stats;
                            const skills = skills_step.skills;
                            self.step.skills.deinit();
                            try self.initConfirmStep(stats, skills);
                        }
                    },
                    .confirm => |confirm_step| {
                        return .{ confirm_step.stats, confirm_step.skills, confirm_step.health };
                    },
                }
            },
        }
    }
    return null;
}

fn showDescription(self: *Self, description: *const g.Description) !void {
    self.description = .init(self.arena.allocator(), w.Window.DEFAULT_MAX_REGION);
    var area = try self.description.?.changeContent(w.TextArea);
    area.* = .initEmpty(self.description.?.allocator());
    for (description.description) |descr_line| {
        try area.printLineFmt("{s}", .{descr_line});
    }
    try self.description.?.formatTitle("{s}", .{description.name});
}

pub fn draw(self: Self, render: g.Render) !void {
    if (self.description) |description| {
        try description.draw(render);
    } else {
        try render.clearDisplay();
        const title_point: p.Point = .point(1, 1);
        try render.drawHorizontalLine('═', title_point.movedTo(.down), g.DISPLAY_COLS);
        try render.drawHorizontalLine('═', .point(g.DISPLAY_ROWS - 1, 1), g.DISPLAY_COLS);
        switch (self.step) {
            .archetype => |archetype| {
                try render.drawTextWithAlign(
                    g.DISPLAY_COLS,
                    "Choose your archetype:",
                    title_point,
                    .normal,
                    .center,
                );
                try archetype.draw(render, ARCHETYPE_AREA_REGION, 0);
                try render.cleanInfo();
                try render.drawLeftButton("Describe", false);
                try render.drawRightButton("Choose", false);
            },
            .skills => |skills| {
                try render.drawTextWithAlign(
                    g.DISPLAY_COLS,
                    "Skills:",
                    title_point,
                    .normal,
                    .center,
                );
                try skills.options.draw(render, SKILLS_AREA_REGION, 0);
                var buf: [15]u8 = undefined;
                try render.drawInfo(
                    try std.fmt.bufPrint(&buf, "{d} points remain", .{skills.remaining_points}),
                );
                try render.drawLeftButton("Back", false);
                if (skills.remaining_points > 0)
                    try render.drawRightButton("Describe", false)
                else
                    try render.drawRightButton("Done", false);
            },
            .confirm => |confirm| {
                try render.drawTextWithAlign(
                    CONFIRM_AREA_REGION.cols,
                    "Start with this character?",
                    title_point,
                    .normal,
                    .center,
                );
                try confirm.description.draw(render);
                try render.cleanInfo();
                try render.drawLeftButton("Back", false);
                try render.drawRightButton("Play", false);
            },
        }
    }
}
