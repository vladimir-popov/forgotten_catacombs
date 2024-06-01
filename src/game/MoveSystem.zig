const game = @import("game.zig");
const cmp = game.components;
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

pub fn handleMove(universe: *game.Universe) anyerror!void {
    const dungeon = &universe.getComponents(game.components.Dungeon)[0];
    var itr = universe.queryComponents2(cmp.Move, cmp.Position);
    while (itr.next()) |components| {
        const move = components[0];
        const position = components[1];
        const new_position = position.movedTo(move.direction);
        if (dungeon.cellAt(new_position)) |cell| {
            switch (cell) {
                .floor => move.doMove(position),
                // .wall => universe.addComponent(entiy),
                else => {},
            }
        }
    }
}
