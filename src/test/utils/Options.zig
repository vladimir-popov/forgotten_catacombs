const std = @import("std");
const g = @import("game");
const p = g.primitives;
const TestSession = @import("TestSession.zig");

const Self = @This();

area: *g.windows.OptionsArea(g.Entity),
test_session: *TestSession,

/// Selects an option with the passed name or throws error.
/// If the options was found, a button is pressed to choose that option.
/// To find an option this function checks the label of every item for containing the passed name.
pub fn choose(self: Self, option_name: []const u8) !void {
    for (self.area.options.items, 0..) |option, idx| {
        if (std.mem.containsAtLeast(u8, option.label(), 1, option_name)) {
            try self.area.selectLine(idx);
            try self.test_session.pressButton(.a);
            return;
        }
    }
    return error.OptionWasNotFound;
}

pub fn chooseById(self: Self, item_id: g.Entity) !void {
    for (self.area.options.items, 0..) |option, idx| {
        if (option.item.eql(item_id)) {
            try self.area.selectLine(idx);
            try self.test_session.pressButton(.a);
            return;
        }
    }
    return error.OptionWasNotFound;
}
