const std = @import("std");
const game = @import("game.zig");
const cmp = game.components;
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

const log = std.log.scoped(.movement_system);

pub fn handleMove(universe: *game.Universe) anyerror!void {
    const player_entity = universe.getComponents(cmp.Level)[0].player;
    const dungeon = &universe.getComponents(cmp.Dungeon)[0];
    const screen = &universe.getComponents(cmp.Screen)[0];
    var itr = universe.queryComponents2(cmp.Move, cmp.Position);
    while (itr.next()) |components| {
        const entity = components[0];
        const move = components[1];
        var position = components[2];
        if (move.direction) |direction| {
            const new_point = position.point.movedTo(direction);
            if (dungeon.cellAt(new_point)) |cell| {
                switch (cell) {
                    .floor, .opened_door => {
                        move.applyTo(position);
                        if (entity != player_entity) {
                            continue;
                        }
                        if (direction == .up and new_point.row < screen.innerRegion().top_left.row)
                            screen.move(direction);
                        if (direction == .down and new_point.row > screen.innerRegion().bottomRight().row)
                            screen.move(direction);
                        if (direction == .left and new_point.col < screen.innerRegion().top_left.col)
                            screen.move(direction);
                        if (direction == .right and new_point.col > screen.innerRegion().bottomRight().col)
                            screen.move(direction);
                    },
                    .closed_door => {
                        try dungeon.openDoor(new_point);
                        move.ignore();
                    },
                    else => {},
                }
            }
        }
    }
}
