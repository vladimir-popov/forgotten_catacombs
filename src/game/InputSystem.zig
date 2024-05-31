const game = @import("game.zig");

const Universe = game.ForgottenCatacomb.Universe;

fn handleInput(universe: *Universe) anyerror!void {
    const btn = try universe.runtime.readButton() orelse return;
    if (!game.Button.isMove(btn)) return;

    universe.fireEvent(game.Events.buttonWasPressed);

    const level = universe.getComponents(game.Level)[0];
    var entities = universe.entitiesIterator();
    while (entities.next()) |entity| {
        if (universe.getComponent(entity, game.Position)) |position| {
            var new_position: game.Position = position.*;
            if (btn & game.Button.Up > 0)
                new_position.row -= 1;
            if (btn & game.Button.Down > 0)
                new_position.row += 1;
            if (btn & game.Button.Left > 0)
                new_position.col -= 1;
            if (btn & game.Button.Right > 0)
                new_position.col += 1;

            if (!level.dungeon.walls.isSet(new_position.row, new_position.col))
                position.* = new_position;
        }
    }
}

