const std = @import("std");
const g = @import("game");

const Args = @import("Args.zig");
const Logger = @import("Logger.zig");
// exported for tests
pub const tty = @import("tty.zig");
pub const TtyRuntime = @import("TtyRuntime.zig");

pub const std_options: std.Options = .{
    .logFn = Logger.writeLog,
    .log_level = .info,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .default, .level = .debug },
        .{ .scope = .cheats, .level = .debug },
        .{ .scope = .game_session, .level = .debug },
        // .{ .scope = .actions, .level = .debug },
        // .{ .scope = .registry, .level = .debug },
        // .{ .scope = .ai, .level = .debug },
        // .{ .scope = .cave, .level = .debug },
        // .{ .scope = .events, .level = .debug },
        // .{ .scope = .game, .level = .debug },
        .{ .scope = .game_session, .level = .info },
        // .{ .scope = .inventory_mode, .level = .debug },
        // .{ .scope = .modify_mode, .level = .debug },
        // .{ .scope = .level, .level = .debug },
        // .{ .scope = .load_level_mode, .level = .debug },
        // .{ .scope = .looking_around_mode, .level = .debug },
        // .{ .scope = .play_mode, .level = .debug },
        // .{ .scope = .render, .level = .warn },
        // .{ .scope = .save_load_mode, .level = .debug },
        // .{ .scope = .visibility, .level = .debug },
        .{ .scope = .meta, .level = .debug },
        .{ .scope = .journal, .level = .debug },
        .{ .scope = .cmd, .level = .debug },
        // .{ .scope = .windows, .level = .debug },
    },
};

const log = std.log.scoped(.main);

pub const panic = std.debug.FullPanic(handlePanic);

pub fn handlePanic(
    msg: []const u8,
    first_trace_addr: ?usize,
) noreturn {
    TtyRuntime.disableGameMode() catch unreachable;
    std.debug.defaultPanic(msg, first_trace_addr);
}

pub fn main(init: std.process.Init.Minimal) !void {
    const args: Args = .{ .args = init.args };
    const seed = try args.int(u64, "seed") orelse std.crypto.random.int(u64);
    log.info(
        "========================================\nSeed of the game is {d}\n========================================",
        .{seed},
    );

    var gpa = std.heap.DebugAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");
    const alloc = gpa.allocator();

    var single_threaded_io: std.Io.Threaded = .init_single_threaded;

    const use_cheats = args.flag("devmode");
    const use_mouse = args.flag("mouse");
    const preset = if (args.str("preset")) |preset| parsePreset(preset) else null;

    var runtime = try TtyRuntime.TtyRuntime(g.DISPLAY_ROWS + 2, g.DISPLAY_COLS + 2)
        .init(alloc, single_threaded_io.ioBasic(), true, true, use_cheats, use_mouse);
    defer runtime.deinit();

    if (use_cheats) {
        log.warn("The Developer is in the room!", .{});
        if (args.str("cheat")) |value| {
            runtime.cheat = g.Cheat.parse(value);
        }
    }
    var game = try alloc.create(g.Game);
    defer alloc.destroy(game);

    if (preset) |tuple| {
        try game.initNewPreset(alloc, runtime.runtime(), seed, tuple[0], tuple[1]);
    } else {
        try game.init(alloc, runtime.runtime(), seed);
    }
    defer game.deinit();

    try runtime.run(game);
}

fn parsePreset(
    preset_str: []const u8,
) ?struct { g.meta.PlayerArchetype, g.components.Skills } {
    var itr = std.mem.splitScalar(u8, preset_str, ':');
    if (itr.next()) |archetype_str| {
        if (itr.next()) |skills_str| {
            if (parseArchetype(archetype_str)) |archetype| {
                if (parseSkills(skills_str)) |skills| {
                    return .{ archetype, skills };
                }
            }
        }
    }
    log.err(
        \\Wrong argument. The value from `--preset=<value>` should follow format: <archetype>:<skills>
        \\Where <archetype> is one of possible character archetype:
        \\
        \\  (adv)enturer
        \\  (arc)heologist
        \\  (van)dal
        \\  (rog)ue
        \\
        \\and <skills> is a list of skill with 2 spent point in follow order:
        \\
        \\`weapon_mastery`,`mechanics`,`stealth`,`echo_of_knowledge`
        \\
        \\The tail zero skills can be omitted. For example: "1,1" is equal to "1,1,0,0".
        \\
    ,
        .{},
    );
    return null;
}

fn parseArchetype(str: []const u8) ?g.meta.PlayerArchetype {
    if (std.meta.stringToEnum(g.meta.PlayerArchetype, str)) |archetype| {
        return archetype;
    }
    if (std.mem.eql(u8, "adv", str))
        return .adventurer;
    if (std.mem.eql(u8, "arc", str))
        return .archeologist;
    if (std.mem.eql(u8, "van", str))
        return .vandal;
    if (std.mem.eql(u8, "rog", str))
        return .rogue;

    return null;
}

fn parseSkills(str: []const u8) ?g.components.Skills {
    var result: g.components.Skills = .zeros;
    var i: usize = 0;
    var spent_points: i4 = 0;
    var itr = std.mem.splitScalar(u8, str, ',');
    while (itr.next()) |number| {
        result.values.values[i] = std.fmt.parseInt(i4, number, 10) catch {
            log.err("Invalid number: {s}", .{number});
            return null;
        };
        spent_points += result.values.values[i];
        i += 1;
    }
    if (spent_points < 2) {
        log.err("Not enought skill points. Spent {d}, but should be spent 2.", .{spent_points});
        return null;
    }
    if (spent_points > 2) {
        log.err("Too many skill points spent in total: {d}. You should spent only 2.", .{spent_points});
        return null;
    }

    return result;
}
