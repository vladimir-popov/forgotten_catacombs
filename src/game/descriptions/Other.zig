const Description = @import("../Description.zig");

closed_door: Description = .{
    .name = "Closed door",
    .description = &.{
        "The  door  stands shut, silent  and",
        "uninviting,  hidding  whatever lies",
        "beyond.",
    },
},
ladder_down: Description = .{ .name = "Ladder down" },
ladder_to_caves: Description = .{ .name = "Entrance to caves" },
ladder_up: Description = .{ .name = "Ladder up" },
oil_lamp: Description = .{
    .name = "Oil lamp",
    .description = &.{
        "A simple metal lamp filled with",
        "oil, its flickering flame casts",
        "light into the darkest corners.",
    },
},
opened_door: Description = .{
    .name = "Opened door",
    .description = &.{
        "A  doorway  stands open, offering a",
        "glimpse  intothe  space  that  lies",
        "ahead.",
    },
},
pile: Description = .{
    .name = "Pile of items",
    .description = &.{
        "A heap of miscellaneous gear.",
        "Search it to see what’s useful.",
    },
},
gold_pile: Description = .{
    .name = "Gold",
    .description = &.{
        "A  pile  of  dimly  glinting",
        "coins, carelessly swept into",
        "one place.",
    },
},
player: Description = .{ .name = "You" },
scientist: Description = .{ .name = "Scientist" },
teleport: Description = .{ .name = "Teleport" },
traider: Description = .{ .name = "Traider" },
trap: Description = .{
    .name = "Trap",
    .description = &.{
        "Hidden spikes burst from the ground",
        "impaling anything standing above.",
    },
},
unknown_key: Description = .{ .name = "Unknown" },
wharf: Description = .{ .name = "Wharf" },
