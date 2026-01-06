const std = @import("std");
const g = @import("game");
const p = g.primitives;
const TestSession = @import("TestSession.zig");

const Self = @This();

options_area: *g.windows.OptionsArea(g.Entity),
test_session: *TestSession,

/// Selects an option with the passed name or throws error.
/// If the options was found, a button is pressed to choose that option.
/// To find an option this function checks the label of every item for containing the passed name.
pub fn choose(self: Self, option_name: []const u8) !void {
    for (self.options_area.options.items, 0..) |option, idx| {
        if (std.mem.containsAtLeast(u8, option.label(), 1, option_name)) {
            try self.options_area.selectLine(idx);
            try self.test_session.pressButton(.a);
            return;
        }
    }
    return error.OptionWasNotFound;
}

pub fn chooseById(self: Self, item_id: g.Entity) !void {
    for (self.options_area.options.items, 0..) |option, idx| {
        if (option.item.eql(item_id)) {
            try self.options_area.selectLine(idx);
            try self.test_session.pressButton(.a);
            return;
        }
    }
    return error.OptionWasNotFound;
}

pub fn chooseByIndex(self: Self, idx: usize) !void {
    try self.options_area.selectLine(idx);
    try self.test_session.pressButton(.a);
}

pub fn contains(self: Self, item_id: g.Entity) bool {
    for (self.options_area.options.items) |option| {
        if (option.item.eql(item_id)) {
            return true;
        }
    }
    return false;
}
