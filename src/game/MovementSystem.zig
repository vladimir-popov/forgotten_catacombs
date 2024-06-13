const std = @import("std");
const game = @import("game.zig");
const cmp = game.components;
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

const log = std.log.scoped(.movement_system);

pub fn handleMove(universe: *game.Universe) anyerror!void {
    const dungeon = universe.root.dungeon;
    var itr = universe.queryComponents2(cmp.Move, cmp.Position);
    while (itr.next()) |components| {
        const entity = components[0];
        const move = components[1];
        const position = components[2];
        if (move.direction) |direction| {
            // try to move:
            const new_point = position.point.movedTo(direction);
            if (dungeon.cellAt(new_point)) |cell| {
                switch (cell) {
                    .floor => {
                        doMove(universe, move, position, entity);
                    },
                    .door => |door| {
                        if (door == .opened) {
                            doMove(universe, move, position, entity);
                        } else {
                            dungeon.openDoor(new_point);
                            move.cancel();
                        }
                    },
                    else => {},
                }
            }
        }
    }
}

fn doMove(universe: *game.Universe, move: *cmp.Move, position: *cmp.Position, entity: game.Entity) void {
    const orig_point = position.point;
    const direction = move.direction.?;
    move.applyTo(position);

    if (entity != universe.root.player) {
        return;
    }

    // keep player on the screen:
    const screen = &universe.root.screen;
    const inner_region = screen.innerRegion();
    const dungeon = universe.root.dungeon;
    const new_point = position.point;
    if (direction == .up and new_point.row < inner_region.top_left.row)
        screen.move(direction);
    if (direction == .down and new_point.row > inner_region.bottomRightRow())
        screen.move(direction);
    if (direction == .left and new_point.col < inner_region.top_left.col)
        screen.move(direction);
    if (direction == .right and new_point.col > inner_region.bottomRightCol())
        screen.move(direction);

    // maybe stop keep moving:
    var neighbors = dungeon.cellsAround(new_point) orelse return;
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
}
