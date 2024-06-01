const game = @import("game.zig");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

fn handleInput(universe: *game.Universe) anyerror!void {
    const btn = try universe.runtime.readButton() orelse return;
    if (!game.Button.isMove(btn)) return;

    universe.fireEvent(game.Events.buttonWasPressed);

    const player_entity = universe.getComponents(game.components.Level)[0].player;
    if (universe.getComponent(player_entity, game.components.Sprite)) |player| {
        if (btn.isMove()) {
            const direction = if (btn & game.Button.Up > 0)
                p.Direction.up
            else if (btn & game.Button.Down > 0)
                p.Direction.down
            else if (btn & game.Button.Left > 0)
                p.Direction.left
            else
                p.Direction.right;

            universe.addComponent(
                player,
                game.components.Move{
                    .entity = player_entity,
                    .position = &player.position,
                    .move = direction,
                },
            );
        }
    }
}
