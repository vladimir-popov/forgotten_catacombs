const std = @import("std");
const g = @import("game");
const c = g.components;
const p = g.primitives;
const Options = @import("Options.zig");
const TestSession = @import("TestSession.zig");

const Self = @This();

test_session: *TestSession,

fn tradingMode(self: Self) *g.GameSession.TradingMode {
    return &self.test_session.session.mode.trading;
}

pub fn isClosed(self: Self) bool {
    return self.test_session.session.mode != .trading;
}

pub fn close(self: Self) !void {
    std.debug.assert(self.tradingMode().actions_window == null);
    std.debug.assert(self.tradingMode().description_window == null);
    try self.test_session.pressButton(.b);
}

pub fn currentShop(self: Self) *c.Shop {
    return self.tradingMode().shop;
}

/// Selects the item with passed name in the active tab, or throws an error.
/// If the item was found, the button is pressed and Options available for the item is returned.
pub fn chooseItemByName(self: Self, name: []const u8) !Options {
    const options = Options{
        .options_area = &self.tradingMode().main_window.activeTab().area.content,
        .test_session = self.test_session,
    };
    try options.choose(name);
    return .{
        .test_session = self.test_session,
        .options_area = &self.tradingMode().actions_window.?.content.content,
    };
}

pub fn chooseItemById(self: Self, item: g.Entity) !Options {
    const options = Options{
        .options_area = &self.tradingMode().main_window.activeTab().area.content,
        .test_session = self.test_session,
    };
    try options.chooseById(item);
    return .{
        .test_session = self.test_session,
        .options_area = &self.tradingMode().actions_window.?.content.content,
    };
}

pub fn chooseItemByIndex(self: Self, idx: usize) !Options {
    const options = Options{
        .options_area = &self.tradingMode().main_window.activeTab().area.content,
        .test_session = self.test_session,
    };
    try options.chooseByIndex(idx);
    return .{
        .test_session = self.test_session,
        .options_area = &self.tradingMode().actions_window.?.content.content,
    };
}
