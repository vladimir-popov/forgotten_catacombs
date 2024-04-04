const std = @import("std");
const ecs = @import("ecs.zig");
const cmp = @import("components.zig");
const Runtime = @import("Runtime.zig");

/// The global state of the game
const Game = ecs.Game(cmp.AllComponents, Runtime, Runtime.Error);

fn render(game: *Game, runtime: *Runtime) Runtime.Error!void {
    _ = runtime;
    var itr = game.entities.entitiesIterator();
    while (itr.next()) |entity| {
        if (game.components.getForEntity(entity.*, cmp.Position)) |position| {
            std.debug.print("{any}\n", .{position});
        }
    }
}

test {
    var runtime = Runtime{};
    var game = try Game.init(std.testing.allocator);
    defer game.deinit();

    const entity = try game.entities.newEntity();
    try game.components.addToEntity(entity, cmp.Position, .{ .row = 1, .col = 2 });

    try game.registerSystem(render);

    try game.tick(&runtime);
}
