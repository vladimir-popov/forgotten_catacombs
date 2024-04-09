const cmp = @import("components.zig");

pub fn Player(entity_builder: anytype) void {
    entity_builder.addComponent(cmp.Position, .{ .row = 2, .col = 2 });
    entity_builder.addComponent(cmp.Sprite, .{ .letter = "@" });
}
