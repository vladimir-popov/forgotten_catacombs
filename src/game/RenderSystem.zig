const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const cmp = game.components;

pub fn render(universe: *game.Universe) anyerror!void {
    if (!(universe.isEventFired(game.Events.gameHasBeenInitialized) or universe.isEventFired(game.Events.buttonWasPressed)))
        return;

    const screen = &universe.getComponents(cmp.Screen)[0];

    const dungeon = &universe.getComponents(cmp.Dungeon)[0];
    try universe.runtime.drawDungeon(screen, dungeon);

    var itr = universe.queryComponents2(cmp.Sprite, cmp.Position);
    while (itr.next()) |components| {
        const sprite = components[1];
        const position = components[2];
        if (screen.region.containsPoint(position.point)) {
            try universe.runtime.drawSprite(screen, sprite, position);
        }
    }
}
