const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

const log = std.log.scoped(.cheats);

var global_debug_shop: ?*c.Shop = null;

const items_suggestions: [g.entities.presets.Items.fields.values.len][]const u8 = blk: {
    var suggestions: [g.entities.presets.Items.fields.values.len][]const u8 = undefined;
    const items = std.enums.values(g.entities.presets.Items.Tag);
    for (items, 0..) |item, i| {
        suggestions[i] = @tagName(item);
    }
    break :blk suggestions;
};

pub const Cheat = union(enum) {
    /// Tag is a name of the cheat.
    /// For some cheats it's enough, but some cheats have additional arguments.
    pub const Tag = std.meta.Tag(Cheat);

    /// Total count of defined cheats.
    pub const count = std.meta.fields(Tag).len;

    /// Prints to log all components of the entity
    dump_entity: g.Entity,

    /// Prints to log a Dijkstra map
    dump_vector_field,

    /// Creates a new item and put it to player's inventory
    get_item: g.entities.presets.Items.Tag,

    // Moves the player to the point on the screen (1-based).
    goto: p.Point,

    /// Moves the player to a ladder lead to an upper level.
    move_player_to_ladder_up,

    /// Moves the player to a ladder lead to an lower level.
    move_player_to_ladder_down,

    /// Adds entity id to the journal
    recognize: g.Entity,

    /// Sets up a passed count of health point to the player.
    set_health: u8,

    /// This cheat works only in trading mode, and sets up the amount of money depending on
    /// the active tab:
    ///  - for Buying tab the balance of the shop will be changed;
    ///  - for Selling tab the player's balance will be changed.
    set_money: u16,

    /// Switches the game to the Trading mode with a special debug trader.
    /// By default the trader has arbitrary number of random items to sell.
    trade,

    /// Replaces a current visibility strategy to "show all"
    turn_light_on,

    /// Replaces a current visibility strategy to appropriate for a current level.
    turn_light_off,

    pub fn parseArgs(tag: Tag, args_str: []const u8) ?Cheat {
        const args = std.mem.trim(u8, args_str, " ");
        switch (tag) {
            .get_item => if (std.meta.stringToEnum(g.entities.presets.Items.Tag, args)) |item| {
                return .{ .get_item = item };
            } else {
                log.warn("Wrong arguments '{s}' for 'get' command.", .{args});
            },
            .goto => {
                var itr = std.mem.tokenizeScalar(u8, args, ' ');
                if (itr.next()) |a_str|
                    if (tryParseDecimal(u8, a_str)) |a|
                        if (itr.next()) |b_str|
                            if (tryParseDecimal(u8, b_str)) |b| {
                                return .{ .goto = p.Point.init(a, b) };
                            };
                log.warn(
                    \\Wrong arguments '{s}' for 'goto' command. 
                    \\It expects a number of the target row and a number of the target column
                    \\in the dungeon's coordinates.
                ,
                    .{args},
                );
            },
            .recognize => if (tryParseDecimal(u32, args)) |entity_id| {
                return .{ .recognize = .{ .id = entity_id } };
            } else {
                log.warn(
                    "Wrong arguments '{s}' for 'recognize' command. It expects an entity id.",
                    .{args},
                );
            },
            .set_health => if (tryParseDecimal(u8, args)) |hp| {
                return .{ .set_health = hp };
            } else {
                log.warn(
                    "Wrong arguments '{s}' for 'set health' command. It expects a number value to set.",
                    .{args},
                );
            },
            .set_money => if (tryParseDecimal(u16, args)) |money| {
                return .{ .set_money = money };
            } else {
                log.warn(
                    "Wrong arguments '{s}' for 'set money' command. It expects a number value to set.",
                    .{args},
                );
            },
            .dump_entity => if (tryParseDecimal(u32, args)) |entity_id| {
                return .{ .dump_entity = .{ .id = entity_id } };
            } else {
                log.warn(
                    "Wrong arguments '{s}' for 'dump entity' command. It expects an entity id.",
                    .{args},
                );
            },
            .dump_vector_field => return .dump_vector_field,
            .move_player_to_ladder_up => return .move_player_to_ladder_up,
            .move_player_to_ladder_down => return .move_player_to_ladder_down,
            .trade => return .trade,
            .turn_light_on => return .turn_light_on,
            .turn_light_off => return .turn_light_off,
        }
        return null;
    }

    inline fn tryParseDecimal(comptime U: type, str: []const u8) ?U {
        return std.fmt.parseInt(
            U,
            std.mem.trim(u8, str, " \t"),
            10,
        ) catch null;
    }

    /// Returns an array of string representation of all cheats sorted alphabetically.
    pub inline fn allAsStrings() [count][]const u8 {
        var strings: [count][]const u8 = undefined;
        inline for (std.meta.fields(Tag), 0..) |f, i| {
            const tag: Tag = @enumFromInt(f.value);
            strings[i] = toString(tag);
        }
        std.mem.sort([]const u8, &strings, {}, strLessThan);
        return strings;
    }
    fn strLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.order(u8, lhs, rhs) == .lt;
    }

    pub inline fn toString(self: Cheat.Tag) []const u8 {
        return switch (self) {
            .dump_entity => "dump entity",
            .dump_vector_field => "dump vectors",
            .get_item => "get",
            .goto => "goto",
            .move_player_to_ladder_down => "down ladder",
            .move_player_to_ladder_up => "up ladder",
            .recognize => "recognize",
            .set_health => "set health",
            .set_money => "set money",
            .trade => "trade",
            .turn_light_off => "light off",
            .turn_light_on => "light on",
        };
    }

    pub fn parse(str: []const u8) ?union(enum) { cheat: Cheat, tag: Tag } {
        const tstr = std.mem.trim(u8, str, " ");
        inline for (std.meta.fields(Tag)) |f| {
            const tag: Tag = @enumFromInt(f.value);
            const tag_str = toString(tag);
            if (std.mem.startsWith(u8, tstr, tag_str)) {
                if (Cheat.parseArgs(tag, tstr[tag_str.len..])) |cheat|
                    return .{ .cheat = cheat }
                else if (tstr.len == tag_str.len)
                    return .{ .tag = tag };
            }
        }
        return null;
    }

    /// Some cheats can be interpreted as game actions.
    pub fn toAction(self: Cheat, session: *g.GameSession) !?g.actions.Action {
        switch (self) {
            .move_player_to_ladder_up => {
                var itr = session.registry.query2(c.Ladder, c.Position);
                while (itr.next()) |tuple| {
                    if (tuple[1].direction == .up) {
                        return movePlayerToPoint(tuple[2].place);
                    }
                }
            },
            .move_player_to_ladder_down => {
                var itr = session.registry.query2(c.Ladder, c.Position);
                while (itr.next()) |tuple| {
                    if (tuple[1].direction == .down) {
                        return movePlayerToPoint(tuple[2].place);
                    }
                }
            },
            .goto => |goto| {
                const screen_corner = session.viewport.region.top_left;
                return movePlayerToPoint(.{
                    .row = goto.row + screen_corner.row - 1,
                    .col = goto.col + screen_corner.col - 1,
                });
            },
            .trade => {
                if (global_debug_shop) |shop| {
                    shop.deinit();
                } else {
                    global_debug_shop = try session.arena.allocator().create(c.Shop);
                }
                global_debug_shop.?.* = try c.Shop.empty(session.arena.allocator(), 1.0, 200);
                try g.meta.fillShop(global_debug_shop.?, &session.registry, session.prng.next());
                return .{ .trade = global_debug_shop.? };
            },
            else => return null,
        }
        return null;
    }

    pub fn suggestions(tag: Tag) ?[]const []const u8 {
        return switch (tag) {
            .get_item => &items_suggestions,
            else => null,
        };
    }

    inline fn movePlayerToPoint(place: p.Point) g.actions.Action {
        return .{ .move = g.actions.Action.Move{ .target = .{ .new_place = place } } };
    }
};

test "list of all cheats in string form" {
    for (Cheat.allAsStrings()) |cheat_str| {
        std.debug.print("{s}\n", .{cheat_str});
    }
}

test "light on" {
    try std.testing.expectEqual(.turn_light_on, Cheat.parse("light on").?.cheat);
}

test "goto" {
    try std.testing.expectEqual(Cheat{ .goto = p.Point.init(2, 3) }, Cheat.parse("goto 2 3").?.cheat);
}

test "set health" {
    try std.testing.expectEqual(Cheat{ .set_health = 42 }, Cheat.parse("set health  42").?.cheat);
}
