//! This is the factories of the levels.
//! It bind levels with dungeons, visibility strategies, add entities on the levels.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const ecs = g.ecs;
const p = g.primitives;

const log = std.log.scoped(.levels);

/// Initializes the first game level.
/// @param level should be not initialized.
pub fn firstLevel(
    level: *g.Level,
    alloc: std.mem.Allocator,
    player: c.Components,
    first_visit: bool,
) !void {
    level.arena = std.heap.ArenaAllocator.init(alloc);
    log.debug("Begin creation of the first level. Is first visit? {any}", .{first_visit});
    const dungeon = try d.FirstLocation.generateDungeon(&level.arena);
    log.debug("The dungeon has been created successfully", .{});
    try initWithDungeon(
        level,
        0,
        dungeon,
        dungeon.entrance,
        g.visibility.showTheCurrentPlacement,
    );
    log.debug("The level is initialized. Start adding the content.", .{});

    // Add wharf
    _ = try level.addNewEntity(g.entities.wharfEntrance(dungeon.entrance));

    // Add the ladder leads to the bottom dungeons:
    const id = try level.newEntity();
    try level.components.setComponentsToEntity(
        id,
        g.entities.cavesEntrance(id, level.generateNextEntityId(), dungeon.exit),
    );

    // Place the player on the level
    level.player = try level.addNewEntity(player);
    log.debug("The player entity id is {d}", .{level.player});
    if (first_visit)
        try level.components.setToEntity(level.player, c.Position{ .point = dungeon.entrance })
    else
        try level.components.setToEntity(level.player, c.Position{ .point = dungeon.exit });

    // Add the trader
    _ = try level.addNewEntity(g.entities.trader(d.FirstLocation.trader_place));
    // Add the scientist
    _ = try level.addNewEntity(g.entities.scientist(d.FirstLocation.scientist_place));
    // Add the teleport
    _ = try level.addNewEntity(g.entities.teleport(d.FirstLocation.teleport_place));

    // Add doors
    var doors = level.dungeon.doorways.?.iterator();
    while (doors.next()) |entry| {
        entry.value_ptr.door_id = try level.addNewEntity(g.entities.ClosedDoor);
        try level.components.setToEntity(entry.value_ptr.door_id, c.Position{ .point = entry.key_ptr.* });
        log.debug("For the doorway on {any} added closed door with id {d}", .{ entry.key_ptr.*, entry.value_ptr.door_id });
    }
}

pub inline fn cave(
    level: *g.Level,
    alloc: std.mem.Allocator,
    seed: u64,
    depth: u8,
    player: c.Components,
    from_ladder: c.Ladder,
) !void {
    try generate(
        level,
        alloc,
        seed,
        depth,
        d.CavesGenerator(g.DISPLAY_ROWS * 2, g.DISPLAY_COLS * 2){},
        g.visibility.showInRadiusOfSourceOfLight,
        player,
        from_ladder,
    );
}

/// This methods generates a new level of the catacombs.
pub inline fn catacomb(
    level: *g.Level,
    alloc: std.mem.Allocator,
    seed: u64,
    depth: u8,
    player: c.Components,
    from_ladder: c.Ladder,
) !void {
    try generate(
        level,
        alloc,
        seed,
        depth,
        d.CatacombGenerator{},
        if (depth > 3)
            g.visibility.showTheCurrentPlacement
        else
            g.visibility.showTheCurrentPlacementInLight,
        player,
        from_ladder,
    );
}

// The arena should be already initialized
fn initWithDungeon(
    self: *g.Level,
    depth: u8,
    dungeon: d.Dungeon,
    player_place: p.Point,
    visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
) !void {
    self.depth = depth;
    self.next_entity = 0;
    self.entities = std.ArrayListUnmanaged(g.Entity){};
    self.components = try ecs.ComponentsManager(c.Components).init(self.arena.allocator());
    self.map = try g.LevelMap.init(&self.arena, dungeon.rows, dungeon.cols);
    self.dijkstra_map = g.DijkstraMap.init(
        self.arena.allocator(),
        .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 12, .cols = 25 },
        self.obstacles(),
    );
    self.dungeon = dungeon;
    self.player_placement = dungeon.placementWith(player_place).?;
    self.visibility_strategy = visibility_strategy;
}

fn generate(
    level: *g.Level,
    alloc: std.mem.Allocator,
    seed: u64,
    depth: u8,
    generator: anytype,
    visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
    player: c.Components,
    from_ladder: c.Ladder,
) !void {
    level.arena = std.heap.ArenaAllocator.init(alloc);
    log.debug(
        "Generate level {s} on depth {d} with seed {d} from ladder {any}",
        .{ @tagName(from_ladder.direction), depth, seed, from_ladder },
    );
    // This prng is used to generate entity on this level. But the dungeon should have its own prng
    // to be able to be regenerated when the player travels from level to level.
    var prng = std.Random.DefaultPrng.init(seed);
    const dungeon = try generator.generateDungeon(&level.arena, prng.random());
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
    try initWithDungeon(level, depth, dungeon, init_place, visibility_strategy);

    level.next_entity = @max(from_ladder.id, from_ladder.target_ladder) + 1;
    // Add ladder by which the player has come to this level
    try level.addLadder(from_ladder.inverted(), init_place);
    // Generate player on the ladder
    level.player = try level.addNewEntity(player);
    log.debug("The player entity id is {d}", .{level.player});
    try level.components.setToEntity(level.player, c.Position{ .point = init_place });
    // Add ladder to the next level
    try level.addLadder(.{
        .direction = from_ladder.direction,
        .id = level.generateNextEntityId(),
        .target_ladder = level.generateNextEntityId(),
    }, exit_place);

    // Add enemies
    for (0..prng.random().uintLessThan(u8, 10) + 10) |_| {
        try level.addEnemy(prng.random(), g.entities.Rat);
    }

    // Add doors
    if (level.dungeon.doorways) |doorways| {
        var doors = doorways.iterator();
        while (doors.next()) |entry| {
            entry.value_ptr.door_id = try level.addNewEntity(g.entities.ClosedDoor);
            try level.components.setToEntity(entry.value_ptr.door_id, c.Position{ .point = entry.key_ptr.* });
            log.debug(
                "For the doorway on {any} added closed door with id {d}",
                .{ entry.key_ptr.*, entry.value_ptr.door_id },
            );
        }
    }
}
