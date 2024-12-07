const std = @import("std");
const g = @import("../game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;
const CelluralAutomata = @import("CelluralAutomata.zig");

const log = std.log.scoped(.caves_generator);

const CavesGenerator = @This();

pub fn generateDungeon(
    arena: *std.heap.ArenaAllocator,
    rand: std.Random,
) !d.Dungeon {
    const alloc = arena.allocator();

    const generate_arena = try alloc.create(std.heap.ArenaAllocator);
    defer alloc.destroy(generate_arena);

    generate_arena.* = std.heap.ArenaAllocator.init(alloc);
    defer generate_arena.deinit();
    const cellural_automata = CelluralAutomata{ .arena = generate_arena };

    const dungeon = try arena.allocator().create(d.Cave);
    dungeon.* = try d.Cave.init(arena);
    dungeon.cells.copyFrom(
        try cellural_automata.generate(d.Cave.rows, d.Cave.cols, rand),
    );
    dungeon.entrance = dungeon.randomEmptyPlace(rand);
    dungeon.exit = dungeon.randomEmptyPlace(rand);
    return dungeon.dungeon();
}
