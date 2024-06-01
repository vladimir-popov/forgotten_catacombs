const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

pub fn render(universe: *game.Universe) anyerror!void {
    if (!(universe.isEventFired(game.Events.gameHasBeenInitialized) or universe.isEventFired(game.Events.buttonWasPressed)))
        return;

    const screen = universe.getComponents(game.components.Screen)[0];

    const dungeon = &universe.getComponents(game.components.Dungeon)[0];
    try universe.runtime.drawDungeon(dungeon, screen.region);

    var itr = universe.queryComponents2(game.components.Sprite, game.components.Position);
    while (itr.next()) |components| {
        const sprite = components[1];
        const position = components[2].position;
        if (screen.region.containsPoint(position)) {
            try universe.runtime.drawSprite(sprite, position.row, position.col);
        }
    }
}
