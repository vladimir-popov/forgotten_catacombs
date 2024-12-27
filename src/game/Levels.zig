//! This is the factory of the levels.
//! It bind levels with dungeons, visibility strategies, add entities on the levels.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const ecs = g.ecs;
const p = g.primitives;

const Level = @import("Level.zig");

const log = std.log.scoped(.levels);

pub fn firstLevel(
    arena: *std.heap.ArenaAllocator,
    player: c.Components,
    first_visit: bool,
) !*g.Level {
    log.debug("Begin creation of the first level. Is first visit? {any}", .{first_visit});
    const dungeon = (try d.FirstLocation.create(arena)).dungeon();
    log.debug("The dungeon has been created successfully", .{});
    const level = try g.Level.create(
        arena,
        0,
        dungeon,
        dungeon.entrance,
        g.visibility.showTheCurrentPlacement,
    );
    log.debug("The level is initialized. Start adding the content.", .{});

    // Add wharf
    var id = level.newEntity();
    try level.entities.append(id);
    try level.components.setComponentsToEntity(id, g.entities.wharfEntrance(dungeon.entrance));

    // Add the ladder leads to the bottom dungeons:
    id = level.newEntity();
    try level.entities.append(id);
    try level.components.setComponentsToEntity(id, g.entities.cavesEntrance(id, level.newEntity(), dungeon.exit));

    // Generate player on the wharf
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

    return level;
}

pub inline fn cave(
    arena: *std.heap.ArenaAllocator,
    seed: u64,
    depth: u8,
    player: c.Components,
    from_ladder: c.Ladder,
) !*g.Level {
    return try generate(
        arena,
        seed,
        depth,
        d.CavesGenerator{},
        g.visibility.showInRadiusOfSourceOfLight,
        player,
        from_ladder,
    );
}

/// This methods generates a new level of the catacombs.
pub inline fn catacomb(
    arena: *std.heap.ArenaAllocator,
    seed: u64,
    depth: u8,
    player: c.Components,
    from_ladder: c.Ladder,
) !*g.Level {
    return try generate(
        arena,
        seed,
        depth,
        d.CatacombGenerator{},
        if (depth > 3)
            g.visibility.showTheCurrentPlacement
        else
            g.visibility.showInRadiusOfSourceOfLight,
        player,
        from_ladder,
    );
}

fn generate(
    arena: *std.heap.ArenaAllocator,
    seed: u64,
    depth: u8,
    generator: anytype,
    visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
    player: c.Components,
    from_ladder: c.Ladder,
) !*g.Level {
    log.debug(
        "Generate level {s} on depth {d} with seed {d} from ladder {any}",
        .{ @tagName(from_ladder.direction), depth, seed, from_ladder },
    );
    // This prng is used to generate entity on this level. But the dungeon should have its own prng
    // to be able to be regenerated when the player travels from level to level.
    var prng = std.Random.DefaultPrng.init(seed);
    const dungeon = try generator.generateDungeon(arena, prng.random());
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
    const level = try g.Level.create(arena, depth, dungeon, init_place, visibility_strategy);

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
        .id = level.newEntity(),
        .target_ladder = level.newEntity(),
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

    return level;
}
