/// Set of methods to draw the game.
/// Comparing with `AnyRuntime`, this module contains methods
/// to draw objects from the game domain.
///
///   ╔═══════════════════════════════════════╗-------
///   ║                                       ║ |   |
///   ║                                       ║
///   ║                                       ║ S
///   ║                                       ║ c   D
///   ║                                       ║ r   i
///   ║                                       ║ e   s
///   ║                                       ║ e   p
///   ║                                       ║ n   l
///   ║                                       ║     a
///   ║                                       ║ |   y
///   ║═══════════════════════════════════════║---
///   ║HP: 100     Rat:||||||||||||||| Attack ║     |
///   ╚═══════════════════════════════════════╝-------
///   | Zone 0 |        Zone 1       | Zone 2 |
///   |             Stats            | Button |
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.render);

const DrawingMode = g.Runtime.DrawingMode;
const TextAlign = enum { center, left, right };

pub fn Render(comptime rows: u8, cols: u8) type {
    return struct {
        const ROWS: u8 = rows;
        const COLS: u8 = cols;
        const OUT_ZONE_LENGTH = 8;
        const MIDDLE_ZONE_LENGTH = COLS - (OUT_ZONE_LENGTH + 1) * 2 - 2;

        const Self = @This();

        runtime: g.Runtime,
        /// Visible area
        screen: g.Screen,

        pub fn init(runtime: g.Runtime) Self {
            return .{
                .runtime = runtime,
                .screen = g.Screen.init(ROWS - 2, COLS),
            };
        }

        /// Clears the screen and draw all from scratch.
        /// Removes completed animations.
        pub fn redraw(self: Self, session: *g.GameSession, entity_in_focus: ?g.Entity) !void {
            try self.clearDisplay();
            // separate dung and stats:
            try self.runtime.drawHorizontalBorderLine(ROWS - 2, COLS);
            try self.drawScene(session, entity_in_focus);
        }

        pub inline fn clearDisplay(self: Self) !void {
            try self.runtime.clearDisplay();
        }

        /// Draws dungeon, sprites, animations, and stats on the screen.
        /// Removes completed animations.
        pub fn drawScene(self: Self, session: *g.GameSession, entity_in_focus: ?g.Entity) !void {
            try self.drawDungeon(session.level.dungeon);
            try self.drawSprites(session.level, entity_in_focus);
            try self.drawAnimationsFrame(session, entity_in_focus);
            try self.drawInfoBar(session, entity_in_focus);
        }

        pub fn drawDungeon(self: Self, dungeon: g.Dungeon) anyerror!void {
            var itr = dungeon.cellsInRegion(self.screen.region) orelse return;
            var place = self.screen.region.top_left;
            var sprite = c.Sprite{ .codepoint = undefined };
            while (itr.next()) |cell| {
                sprite.codepoint = switch (cell) {
                    .floor => '.',
                    .wall => '#',
                    else => ' ',
                };
                try self.drawSprite(sprite, place, .normal);
                place.move(.right);
                if (!self.screen.region.containsPoint(place)) {
                    place.col = self.screen.region.top_left.col;
                    place.move(.down);
                }
            }
        }

        const ZOrderedSprites = struct { g.Entity, *c.Position, *c.Sprite };
        fn compareZOrder(_: void, a: ZOrderedSprites, b: ZOrderedSprites) std.math.Order {
            if (a[2].z_order < b[2].z_order)
                return .lt
            else
                return .gt;
        }
        /// Draw sprites inside the screen and highlights the sprite of the entity in focus.
        pub fn drawSprites(self: Self, level: g.Level, entity_in_focus: ?g.Entity) !void {
            var visible = std.PriorityQueue(ZOrderedSprites, void, compareZOrder).init(self.runtime.alloc, {});
            defer visible.deinit();

            var itr = level.query().get2(c.Position, c.Sprite);
            while (itr.next()) |tuple| {
                if (self.screen.region.containsPoint(tuple[1].point)) {
                    try visible.add(tuple);
                }
            }
            while (visible.removeOrNull()) |tuple| {
                const mode: g.Runtime.DrawingMode = if (entity_in_focus == tuple[0])
                    .inverted
                else
                    .normal;
                try self.drawSprite(tuple[2].*, tuple[1].point, mode);
            }
        }

        fn drawSprite(
            self: Self,
            sprite: c.Sprite,
            place: p.Point,
            mode: g.Runtime.DrawingMode,
        ) anyerror!void {
            if (self.screen.region.containsPoint(place)) {
                const position_on_display = p.Point{
                    .row = place.row - self.screen.region.top_left.row,
                    .col = place.col - self.screen.region.top_left.col,
                };
                try self.runtime.drawSprite(sprite.codepoint, position_on_display, mode);
            }
        }

        /// Draws a single frame from every animation.
        /// Removes the animation if the last frame was drawn.
        pub fn drawAnimationsFrame(self: Self, session: *g.GameSession, entity_in_focus: ?g.Entity) !void {
            const now: c_uint = self.runtime.currentMillis();
            var itr = session.level.query().get2(c.Position, c.Animation);
            while (itr.next()) |components| {
                const position = components[1];
                const animation = components[2];
                if (animation.frame(now)) |frame| {
                    if (frame > 0 and self.screen.region.containsPoint(position.point)) {
                        const mode: DrawingMode = if (entity_in_focus == components[0])
                            .inverted
                        else
                            .normal;
                        try self.drawSprite(
                            .{ .codepoint = frame },
                            position.point,
                            mode,
                        );
                    }
                } else {
                    try session.level.components.removeFromEntity(components[0], c.Animation);
                }
            }
        }

        /// Draws the hit points of the player, and the name and hit points of the entity in focus.
        pub fn drawInfoBar(self: Self, session: *const g.GameSession, entity_in_focus: ?g.Entity) !void {
            // Draw player's health, or pause mode indicator
            switch (session.mode) {
                .explore => try self.drawZone(0, "Pause", .inverted),
                .play => if (session.level.components.getForEntity(session.level.player, c.Health)) |health| {
                    var buf = [_]u8{0} ** 8;
                    const text = try std.fmt.bufPrint(&buf, "HP: {d}", .{health.current});
                    try self.drawZone(0, text, .normal);
                },
            }
            // Draw the name and health of the entity in focus
            if (entity_in_focus) |entity| {
                var buf: [MIDDLE_ZONE_LENGTH]u8 = undefined;
                inline for (0..MIDDLE_ZONE_LENGTH) |i| buf[i] = ' ';
                var len: usize = 0;
                // Draw entity's name
                if (session.level.components.getForEntity(entity, c.Description)) |desc| {
                    len = (try std.fmt.bufPrint(&buf, "{s}", .{desc.name})).len;
                }
                // Draw enemy's health
                if (entity != session.level.player) {
                    if (session.level.components.getForEntity(entity, c.Health)) |health| {
                        buf[len] = ':';
                        len += 1;
                        const hp = @max(health.current, 0);
                        const free_length = MIDDLE_ZONE_LENGTH - len;
                        const hp_length = @divFloor(free_length * hp, health.max);
                        for (0..hp_length) |i| {
                            buf[len + i] = '|';
                        }
                        len += free_length;
                    }
                }
                try self.drawZone(1, buf[0..len], .normal);
            } else {
                try self.cleanZone(1);
            }
        }

        /// Draws quick action button, or hide it if quick_action is null.
        pub fn drawQuickActionButton(self: Self, quick_action: ?c.Action) !void {
            // Draw the quick action
            if (quick_action) |qa| {
                switch (qa.type) {
                    .wait => try self.drawZone(2, "Wait", .inverted),
                    .open => try self.drawZone(2, "Open", .inverted),
                    .close => try self.drawZone(2, "Close", .inverted),
                    .hit => try self.drawZone(2, "Attack", .inverted),
                    .move_to_level => |ladder| switch (ladder.direction) {
                        .up => try self.drawZone(2, "Go up", .inverted),
                        .down => try self.drawZone(2, "Go down", .inverted),
                    },
                    else => try self.cleanZone(2),
                }
            } else {
                try self.cleanZone(2);
            }
        }

        pub fn drawWelcomeScreen(self: Self) !void {
            try self.runtime.clearDisplay();
            const vertical_middle = ROWS / 2 - 1;
            try self.drawText(COLS, "Welcome", .{ .row = vertical_middle - 1, .col = 1 }, .normal, .center);
            try self.drawText(COLS, "to", .{ .row = vertical_middle, .col = 1 }, .normal, .center);
            try self.drawText(COLS, "Forgotten catacombs", .{ .row = vertical_middle + 1, .col = 1 }, .normal, .center);
        }

        pub fn drawGameOverScreen(self: Self) !void {
            try self.runtime.clearDisplay();
            try self.drawText(COLS, "You are dead", .{ .row = ROWS / 2 - 1, .col = 1 }, .normal, .center);
        }

        inline fn cleanZone(self: Self, comptime zone: u8) !void {
            try self.drawZone(zone, " ", .normal);
        }

        inline fn drawZone(
            self: Self,
            comptime zone: u2,
            text: []const u8,
            mode: DrawingMode,
        ) !void {
            var buf: [MIDDLE_ZONE_LENGTH]u8 = undefined;
            var pos = p.Point{ .row = ROWS - 1, .col = 1 };
            const buf_len: u8 = switch (zone) {
                0 => OUT_ZONE_LENGTH,
                1 => blk: {
                    pos.col = OUT_ZONE_LENGTH + 2;
                    break :blk MIDDLE_ZONE_LENGTH;
                },
                2 => blk: {
                    pos.col = COLS - OUT_ZONE_LENGTH;
                    break :blk OUT_ZONE_LENGTH;
                },
                else => unreachable,
            };
            if (buf_len > 0) {
                for (0..buf_len) |i| buf[i] = ' ';
                const pad: u8 = (buf_len - @min(text.len, buf_len)) / 2;
                std.mem.copyForwards(u8, buf[pad..], text);
                try self.drawText(buf_len, buf[0..buf_len], pos, mode, .left);
            }
        }

        fn drawText(
            self: Self,
            comptime max_length: u8,
            text: []const u8,
            absolut_position: p.Point,
            mode: g.Runtime.DrawingMode,
            aln: TextAlign,
        ) !void {
            const text_length = @min(max_length, text.len);
            var pos = absolut_position;
            switch (aln) {
                .left => {},
                .center => pos.col += (max_length - text_length) / 2,
                .right => pos.col += (max_length - text_length),
            }
            try self.runtime.drawText(text[0..text_length], pos, mode);
        }
    };
}
