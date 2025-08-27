const std = @import("std");
const g = @import("game");
const p = g.primitives;
const Options = @import("Options.zig");
const TestSession = @import("TestSession.zig");

const Self = @This();

test_session: *TestSession,


/// Selects the item with passed name in the active tab, or throws an error.
/// If the item was found, the button is pressed and Options available for the item is returned.
pub fn chooseItemByName(self: Self, name: []const u8) !Options {
    const mode = &self.test_session.session.mode.inventory;
    const options = Options{ .area = &mode.main_window.activeTab().area, .test_session = self.test_session };
    try options.choose(name);
    return .{ .test_session = self.test_session, .area = &mode.actions_window.?.area };
}

pub fn close(self: Self) !void {
    try self.test_session.pressButton(.b);
}
