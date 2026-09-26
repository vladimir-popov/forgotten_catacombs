const std = @import("std");
const g = @import("game");
const c = g.components;
const p = g.primitives;
const w = g.windows;
const Options = @import("Options.zig");
const ModalWindows = @import("ModalWindows.zig");
const TestSession = @import("TestSession.zig");

const Self = @This();

test_session: *TestSession,

fn inventoryMode(self: Self) *g.GameSession.InventoryMode {
    std.debug.assert(self.test_session.session.mode == .inventory);
    return self.test_session.session.mode.inventory;
}

pub fn isClosed(self: Self) bool {
    return self.test_session.session.mode != .inventory;
}

pub fn isInvetoryEmpty(self: Self) bool {
    return self.test_session.session.mode.inventory.inventory.items.size() == 0;
}

pub fn isInvetoryFull(self: Self) bool {
    return self.test_session.session.mode.inventory.inventory.isFull();
}

pub fn isDropEmpty(self: Self) bool {
    return self.test_session.session.mode.inventory.drop == null;
}

pub fn close(self: Self) !void {
    if (self.test_session.session.mode != .inventory) return;

    std.debug.assert(self.inventoryMode().compositor.modal_windows_count == 0);
    try self.test_session.pressButton(.b);
    std.debug.assert(self.test_session.session.mode == .play);
}

/// Selects the item with passed name in the active tab, or throws an error.
/// If the item was found, the button is pressed and modal windows for the item are returned.
pub fn chooseItemByName(self: Self, name: []const u8) !ModalWindows {
    const options = Options{
        .options_area = self.inventoryMode().main_window.activeTab(w.OptionsArea(g.Entity)).?,
        .test_session = self.test_session,
    };
    try options.choose(name);
    return .{ .test_session = self.test_session, .compositor = &self.inventoryMode().compositor };
}

pub fn chooseItemById(self: Self, item: g.Entity) !ModalWindows {
    const options = Options{
        .options_area = self.inventoryMode().main_window.activeTab(w.OptionsArea(g.Entity)).?,
        .test_session = self.test_session,
    };
    try options.chooseById(item);
    return .{ .test_session = self.test_session, .compositor = &self.inventoryMode().compositor };
}

pub fn chooseItemByIndex(self: Self, idx: usize) !ModalWindows {
    const options = Options{
        .options_area = self.inventoryMode().main_window.activeTab(w.OptionsArea(g.Entity)).?,
        .test_session = self.test_session,
    };
    try options.chooseByIndex(idx);
    return .{ .test_session = self.test_session, .compositor = &self.inventoryMode().compositor };
}

pub fn contains(self: Self, item: g.Entity) bool {
    const options = Options{
        .options_area = self.inventoryMode().main_window.activeTab(w.OptionsArea(g.Entity)).?,
        .test_session = self.test_session,
    };
    return options.contains(item);
}

/// Creates a new entity with provided components, adds that entity to the player's inventory,
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
