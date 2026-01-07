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

pub fn close(self: Self) !void {
    std.debug.assert(self.inventoryMode().actions_window == null);
    std.debug.assert(self.inventoryMode().description_window == null);
    try self.test_session.pressButton(.b);
}

/// Selects the item with passed name in the active tab, or throws an error.
/// If the item was found, the button is pressed and Options available for the item is returned.
pub fn chooseItemByName(self: Self, name: []const u8) !Options {
    const options = Options{
        .options_area = &self.inventoryMode().main_window.activeTab().scrollable_area.content,
        .test_session = self.test_session,
    };
    try options.choose(name);
    return .{
        .test_session = self.test_session,
        .options_area = &self.inventoryMode().actions_window.?.scrollable_area.content,
    };
}

pub fn chooseItemById(self: Self, item: g.Entity) !Options {
    const options = Options{
        .options_area = &self.inventoryMode().main_window.activeTab().scrollable_area.content,
        .test_session = self.test_session,
    };
    try options.chooseById(item);
    return .{
        .test_session = self.test_session,
        .options_area = &self.inventoryMode().actions_window.?.scrollable_area.content,
    };
}

pub fn contains(self: Self, item: g.Entity) bool {
    const options = Options{
        .options_area = &self.inventoryMode().main_window.activeTab().area,
        .test_session = self.test_session,
    };
    return options.contains(item);
}

/// Creates a new entity with provided components, add that entity to the player's inventory,
/// and updates the Inventory tab.
pub fn add(self: Self, item: c.Components) !g.Entity {
    const item_id = try self.test_session.session.registry.addNewEntity(item);
    try self.inventoryMode().inventory.items.add(item_id);
    try self.inventoryMode().updateInventoryTab();
    try self.redraw();
    return item_id;
}

pub fn redraw(self: Self) !void {
    try self.inventoryMode().main_window.draw(self.test_session.render);
    self.test_session.runtime.display.merge(self.test_session.runtime.last_frame);
}
