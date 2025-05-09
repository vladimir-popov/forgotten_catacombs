//! This is the factories of the levels.
//! It bind levels with dungeons, visibility strategies, add entities on the levels.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const cp = g.codepoints;
const d = g.dungeon;
const ecs = g.ecs;
const p = g.primitives;

const log = std.log.scoped(.levels);

/// Initializes the first game level.
/// @param level should be not initialized.
pub fn firstLevel(
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    first_visit: bool,
) !void {
    session.level = try g.Level.init(alloc, session, 0, g.visibility.showTheCurrentPlacement);
    log.debug("Begin creation of the first level. Is first visit? {any}", .{first_visit});
    const dungeon = try d.FirstLocation.generateDungeon(&session.level.arena);
    log.debug("The dungeon has been created successfully", .{});
    try initWithDungeon(
        &session.level,
        dungeon,
        dungeon.entrance,
    );
    log.debug("The level is initialized. Start adding the content.", .{});

    // Add wharf
    var entity = try session.entities.addNewEntity(.{
        .description = .{ .key = "whrf" },
        .sprite = .{ .codepoint = cp.ladder_up, .z_order = 2 },
        .position = .{ .point = dungeon.entrance },
    });
    try session.level.addEntity(entity);

    // Add the ladder leads to the bottom dungeons:
    entity = session.entities.newEntity();
    try session.entities.setComponentsToEntity(entity, .{
        .ladder = .{ .direction = .down, .id = entity, .target_ladder = session.entities.newEntity() },
        .description = .{ .key = "cldr" },
        .sprite = .{ .codepoint = cp.ladder_down, .z_order = 2 },
        .position = .{ .point = dungeon.exit },
    });
    try session.level.addEntity(entity);

    // Place the player on the level
    log.debug("The player entity id is {d}", .{session.player.id});
    if (first_visit)
        try session.entities.set(session.player, c.Position{ .point = dungeon.entrance })
    else
        try session.entities.set(session.player, c.Position{ .point = dungeon.exit });

    // Add the trader
    entity = try session.entities.addNewEntity(.{
        .position = .{ .point = d.FirstLocation.trader_place },
        .sprite = .{ .codepoint = cp.human, .z_order = 3 },
        .description = .{ .key = "trdr" },
    });
    try session.level.addEntity(entity);
    // Add the scientist
    entity = try session.entities.addNewEntity(.{
        .position = .{ .point = d.FirstLocation.scientist_place },
        .sprite = .{ .codepoint = cp.human, .z_order = 3 },
        .description = .{ .key = "scnst" },
    });
    try session.level.addEntity(entity);

    // Add the teleport
    entity = try session.entities.addNewEntity(g.entities.teleport(d.FirstLocation.teleport_place));
    try session.level.addEntity(entity);

    // Add doors
    var doors = session.level.dungeon.doorways.?.iterator();
    while (doors.next()) |entry| {
        entry.value_ptr.door_id = try session.entities.addNewEntity(g.entities.ClosedDoor);
        try session.level.addEntity(entry.value_ptr.door_id);
        try session.entities.set(entry.value_ptr.door_id, c.Position{ .point = entry.key_ptr.* });
        log.debug(
            "For the doorway on {any} added closed door with id {d}",
            .{ entry.key_ptr.*, entry.value_ptr.door_id.id },
        );
    }
}

pub inline fn cave(
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    seed: u64,
    depth: u8,
    from_ladder: c.Ladder,
) !void {
    try generate(
        alloc,
        session,
        seed,
        depth,
        d.CavesGenerator(g.DISPLAY_ROWS * 2, g.DISPLAY_COLS * 2){},
        g.visibility.showInRadiusOfSourceOfLight,
        from_ladder,
    );
}

/// This methods generates a new level of the catacombs.
pub inline fn catacomb(
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    seed: u64,
    depth: u8,
    from_ladder: c.Ladder,
) !void {
    try generate(
        alloc,
        session,
        seed,
        depth,
        d.CatacombGenerator{},
        if (depth > 3)
            g.visibility.showTheCurrentPlacement
        else
            g.visibility.showTheCurrentPlacementInLight,
        from_ladder,
    );
}

// The arena should be already initialized
fn initWithDungeon(
    self: *g.Level,
    dungeon: d.Dungeon,
    player_place: p.Point,
) !void {
    self.map = try g.LevelMap.init(&self.arena, dungeon.rows, dungeon.cols);
    self.dijkstra_map = g.DijkstraMap.init(
        self.arena.allocator(),
        .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 12, .cols = 25 },
        self.obstacles(),
    );
    self.dungeon = dungeon;
    self.player_placement = dungeon.placementWith(player_place).?;
}

fn generate(
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    seed: u64,
    depth: u8,
    generator: anytype,
    visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
    from_ladder: c.Ladder,
) !void {
    session.level = try g.Level.init(alloc, session, depth, visibility_strategy);
    log.debug(
        "Generate level {s} on depth {d} with seed {d} from ladder {any}",
        .{ @tagName(from_ladder.direction), depth, seed, from_ladder },
    );
    // This prng is used to generate entity on this level. But the dungeon should have its own prng
    // to be able to be regenerated when the player travels from level to level.
    var prng = std.Random.DefaultPrng.init(seed);
    const dungeon = try generator.generateDungeon(&session.level.arena, prng.random());
    if (std.log.logEnabled(.debug, .levels)) {
        log.debug("The dungeon has been generated", .{});
        dungeon.dumpToLog();
    }

    const init_place = switch (from_ladder.direction) {
        .down => dungeon.entrance,
        .up => dungeon.exit,
    };
    const exit_place = switch (from_ladder.direction) {
        .up => dungeon.entrance,
        .down => dungeon.exit,
    };
    try initWithDungeon(&session.level, dungeon, init_place);

    // Add ladder by which the player has come to this level
    try addLadder(session, from_ladder.inverted(), init_place);
    // Generate player on the ladder
    log.debug("The player entity id is {d}", .{session.player.id});
    try session.entities.set(session.player, c.Position{ .point = init_place });

    // Add ladder to the next level
    try addLadder(session, .{
        .direction = from_ladder.direction,
        .id = session.entities.newEntity(),
        .target_ladder = session.entities.newEntity(),
    }, exit_place);

    // Add enemies
    for (0..prng.random().uintLessThan(u8, 10) + 10) |_| {
        try addEnemy(session, prng.random(), g.entities.Rat);
    }

    // Add doors
    if (session.level.dungeon.doorways) |doorways| {
        var doors = doorways.iterator();
        while (doors.next()) |entry| {
            entry.value_ptr.door_id = try session.entities.addNewEntity(g.entities.ClosedDoor);
            try session.entities.set(entry.value_ptr.door_id, c.Position{ .point = entry.key_ptr.* });
            try session.level.addEntity(entry.value_ptr.door_id);
            log.debug(
                "For the doorway on {any} added closed door with id {d}",
                .{ entry.key_ptr.*, entry.value_ptr.door_id.id },
            );
        }
    }
}

fn addLadder(session: *g.GameSession, ladder: c.Ladder, place: p.Point) !void {
    try session.entities.setComponentsToEntity(ladder.id, g.entities.ladder(ladder));
    try session.entities.set(ladder.id, c.Position{ .point = place });
    try session.level.addEntity(ladder.id);
}

fn addEnemy(session: *g.GameSession, rand: std.Random, enemy: c.Components) !void {
    if (session.level.randomEmptyPlace(rand)) |place| {
        const id = try session.entities.addNewEntity(enemy);
        try session.level.addEntity(id);
        try session.entities.set(id, c.Position{ .point = place });
        const state: c.EnemyState = if (rand.uintLessThan(u8, 5) == 0) .sleeping else .walking;
        try session.entities.set(id, state);
    }
}
