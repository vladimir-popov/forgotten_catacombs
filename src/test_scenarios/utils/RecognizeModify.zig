const std = @import("std");
const g = @import("game");
const c = g.components;
const p = g.primitives;
const Options = @import("Options.zig");
const TestSession = @import("TestSession.zig");

const Self = @This();

test_session: *TestSession,

fn modifyMode(self: Self) *g.GameSession.ModifyMode {
    return &self.test_session.session.mode.modify_recognize;
}

pub fn isClosed(self: Self) bool {
    return self.test_session.session.mode != .modify_recognize;
}

pub fn close(self: Self) !void {
    std.debug.assert(self.modifyMode().actions_window == null);
    std.debug.assert(self.modifyMode().description_window == null);
    try self.test_session.pressButton(.b);
}

pub fn chooseRecognizeTab(self: Self) !void {
    if (self.modifyMode().main_window.active_tab_idx == 1)
        try self.test_session.pressButton(.left);
}

pub fn chooseModifyTab(self: Self) !void {
    if (self.modifyMode().main_window.active_tab_idx == 0)
        try self.test_session.pressButton(.right);
}

/// Selects the item with passed name in the active tab, or throws an error.
/// If the item was found, the button is pressed and Options available for the item is returned.
pub fn chooseItemByName(self: Self, name: []const u8) !Options {
    const options = Options{
        .options_area = &self.modifyMode().main_window.activeTab().scrollable_area.content,
        .test_session = self.test_session,
    };
    try options.choose(name);
    return .{
        .test_session = self.test_session,
        .options_area = &self.modifyMode().actions_window.?.scrollable_area.content,
    };
}

pub fn chooseItemById(self: Self, item: g.Entity) !Options {
    const options = Options{
        .options_area = &self.modifyMode().main_window.activeTab().scrollable_area.content,
        .test_session = self.test_session,
    };
    try options.chooseById(item);
    return .{
        .test_session = self.test_session,
        .options_area = &self.modifyMode().actions_window.?.scrollable_area.content,
    };
}

pub fn chooseItemByIndex(self: Self, idx: usize) !Options {
    const options = Options{
        .options_area = &self.modifyMode().main_window.activeTab().scrollable_area.content,
        .test_session = self.test_session,
    };
    try options.chooseByIndex(idx);
    return .{
        .test_session = self.test_session,
        .options_area = &self.modifyMode().actions_window.?.scrollable_area.content,
    };
}
