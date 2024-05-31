const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const Universe = game.ForgottenCatacomb.Universe;

pub fn render(universe: *game.Universe) anyerror!void {
    if (!(universe.isEventFired(game.Events.gameHasBeenInitialized) or universe.isEventFired(game.Events.buttonWasPressed)))
        return;

    const screen = universe.getComponents(game.components.Screen)[0];

    const dungeon = &universe.getComponents(game.components.Dungeon)[0];
    try universe.runtime.drawDungeon(dungeon, screen.region);

    for (universe.getComponents(game.components.Sprite)) |*sprite| {
        if (screen.region.containsPoint(sprite.position)) {
            try universe.runtime.drawSprite(sprite, sprite.position.row, sprite.position.col);
        }
    }
}
