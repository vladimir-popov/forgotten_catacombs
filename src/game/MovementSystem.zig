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
    blk: while (itr.next()) |components| {
        const entity = components[0];
        const move = components[1];
        const position = components[2];
        if (move.direction) |direction| {
            // try to move:
            const orig_point = position.point;
            const new_point = position.point.movedTo(direction);
            if (dungeon.cellAt(new_point)) |cell| {
                switch (cell) {
                    .floor, .opened_door => {
                        move.applyTo(position);
                        const inner_region = screen.innerRegion();
                        if (entity != player_entity) {
                            continue :blk;
                        }
                        // keep player on the screen:
                        if (direction == .up and new_point.row < inner_region.top_left.row)
                            screen.move(direction);
                        if (direction == .down and new_point.row > inner_region.bottomRightRow())
                            screen.move(direction);
                        if (direction == .left and new_point.col < inner_region.top_left.col)
                            screen.move(direction);
                        if (direction == .right and new_point.col > inner_region.bottomRightCol())
                            screen.move(direction);

                        // maybe stop keep moving:
                        var neighbors = dungeon.cellsAround(new_point) orelse continue :blk;
                        while (neighbors.next()) |neighbor| {
                            if (std.meta.eql(neighbors.cursor, orig_point))
                                continue;
                            if (std.meta.eql(neighbors.cursor, new_point))
                                continue;
                            switch (neighbor) {
                                // keep moving
                                .floor, .wall => {},
                                // stop
                                else => move.cancel(),
                            }
                        }
                    },
                    .closed_door => {
                        try dungeon.openDoor(new_point);
                        move.cancel();
                    },
                    else => {},
                }
            }
        }
    }
}
