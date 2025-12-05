const std = @import("std");
const g = @import("game");
const c = g.components;
const p = g.primitives;
const Options = @import("Options.zig");
const TestSession = @import("TestSession.zig");

const Self = @This();

test_session: *TestSession,

fn inventoryMode(self: Self) *g.GameSession.InventoryMode {
    return &self.test_session.session.mode.inventory;
}

pub fn isClosed(self: Self) bool {
    return self.test_session.session.mode != .inventory;
}

/// Selects the item with passed name in the active tab, or throws an error.
/// If the item was found, the button is pressed and Options available for the item is returned.
pub fn chooseItemByName(self: Self, name: []const u8) !Options {
    const options = Options{
        .options_area = &self.inventoryMode().main_window.activeTab().area.content,
        .test_session = self.test_session,
    };
    try options.choose(name);
    return .{
        .test_session = self.test_session,
        .options_area = &self.inventoryMode().actions_window.?.content.content,
    };
}

pub fn chooseItemById(self: Self, item: g.Entity) !Options {
    const options = Options{
        .options_area = &self.inventoryMode().main_window.activeTab().area.content,
        .test_session = self.test_session,
    };
    try options.chooseById(item);
    return .{
        .test_session = self.test_session,
        .options_area = &self.inventoryMode().actions_window.?.content.content,
    };
}

pub fn contains(self: Self, item: g.Entity) bool {
    const options = Options{
        .options_area = &self.inventoryMode().main_window.activeTab().area,
        .test_session = self.test_session,
    };
    return options.contains(item);
}

pub fn add(self: Self, item: c.Components) !g.Entity {
    const item_id = try self.test_session.session.registry.addNewEntity(item);
    try self.inventoryMode().inventory.items.add(item_id);
    try self.inventoryMode().updateInventoryTab();
    return item_id;
}
