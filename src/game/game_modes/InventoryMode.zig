//! ```
//!                             The main window with two tabs:
//! ╔════════════════════════════════════════╗     ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║     ║╔══════════════════╔══════════════════╗ ║
//! ║ ║    Inventory    ║        Drop       ║║     ║║    Inventory     ║       Drop       ║ ║
//! ║╔╝                 ╚═══════════════════║║     ║║══════════════════╝                  ╚╗║
//! ║║░\░Club░░░░░░░░░░░░░░░░░░░░░░░░░[x]░░░║║     ║║ / Torch                              ║║
//! ║║   Apple                        [x]   ║║     ║║                                      ║║
//! ║║                                      ║║     ║║                                      ║║
//! ║║                                      ║║     ║║                                      ║║
//! ║║                                      ║║     ║║                                      ║║
//! ║║                                      ║║     ║║                                      ║║
//! ║║                                      ║║     ║║                                      ║║
//! ║╚══════════════════════════════════════╝║     ║╚══════════════════════════════════════╝║
//! ║════════════════════════════════════════║     ║════════════════════════════════════════║
//! ║    000$             Close       Choose ║     ║                     Close       Choose ║
//! ╚════════════════════════════════════════╝     ╚════════════════════════════════════════╝
//!
//!                                      Modal windows:
//! ╔════════════════════════════════════════╗     ╔════════════════════════════════════════╗
//! ║ ╔══════════════════╗══════════════════╗║     ║ ╔══════════════════╗══════════════════╗║
//! ║ ║    Inventory     ║        Drop      ║║     ║ ║    Inventory     ║       Drop       ║║
//! ║╔╝                  ╚══════════════════║║     ║╔╝                  ╚══════════════════║║
//! ║║ ┌───────────────────────────────────┐║║     ║║                                      ║║
//! ║║ │Use                                │║║     ║║ ┌────────────────Club───────────────┐║║
//! ║║ │Drop                               │║║     ║║ │ Id: 12                            │║║
//! ║║ │Describe                           │║║     ║║ │ Damage: 2-5                       │║║
//! ║║ └───────────────────────────────────┘║║     ║║ └───────────────────────────────────┘║║
//! ║║                                      ║║     ║║                                      ║║
//! ║║                                      ║║     ║║                                      ║║
//! ║╚══════════════════════════════════════╝║     ║╚══════════════════════════════════════╝║
//! ║════════════════════════════════════════║     ║════════════════════════════════════════║
//! ║    000$             Cancel       Use   ║     ║     000$                        Close  ║
//! ╚════════════════════════════════════════╝     ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.inventory_mode);

const Self = @This();

alloc: std.mem.Allocator,
session: *g.GameSession,
inventory: *c.Inventory,
equipment: *c.Equipment,
/// The entity under the player's feet. Can be a pile or a single item
drop: ?g.Entity,
main_window: w.WindowWithTabs,
description_window: ?w.ModalWindow = null,
actions_window: ?w.OptionsWindow(g.Entity) = null,

pub fn init(
    self: *Self,
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    equipment: *c.Equipment,
    inventory: *c.Inventory,
    drop: ?g.Entity,
) !void {
    log.debug("Init inventory with drop {any}", .{drop});
    self.* = .{
        .alloc = alloc,
        .session = session,
        .equipment = equipment,
        .inventory = inventory,
        .drop = drop,
        .main_window = w.WindowWithTabs.init(self),
    };
    self.main_window.addTab("Inventory", "Close", "Choose");
    try self.updateInventoryTab();

    if (drop) |item| {
        try self.addDropTab(item);
    }
    try self.draw();
}

// TODO use arena
pub fn deinit(self: *Self) void {
    if (self.description_window) |*window| {
        window.deinit(self.alloc);
    }
    if (self.actions_window) |*window| {
        window.deinit(self.alloc);
    }
    self.main_window.deinit(self.alloc);
}

pub fn tick(self: *Self) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.description_window) |*window| {
            if (try window.handleButton(btn)) {
                std.log.debug("Close description window", .{});
                try window.close(self.alloc, self.session.render, .fill_region);
                self.description_window = null;
            }
        } else if (self.actions_window) |*window| {
            switch (try window.handleButton(btn)) {
                .close_btn, .choose_btn => {
                    std.log.debug("Close actions window", .{});
                    try window.close(self.alloc, self.session.render, .fill_region);
                    self.actions_window = null;
                },
                else => {},
            }
        } else {
            if (try self.main_window.handleButton(btn)) {
                try self.session.play(null);
                return;
            }
        }
        try self.draw();
    }
}

fn draw(self: *Self) !void {
    if (self.description_window) |*window| {
        log.debug("Draw description window", .{});
        try window.draw(self.session.render);
    } else if (self.actions_window) |*window| {
        log.debug("Draw actions window", .{});
        try window.draw(self.session.render);
    } else {
        log.debug("Draw main window tab {d}", .{self.main_window.active_tab_idx});
        try self.main_window.draw(self.session.render);
        var buf: [10]u8 = undefined;
        const money = self.session.registry.getUnsafe(self.session.player, c.Wallet).money;
        try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "{d}$", .{money}));
    }
}

fn tabWithInventory(self: *Self) *w.WindowWithTabs.Tab {
    return &self.main_window.tabs[0];
}

fn tabWithDrop(self: *Self) ?*w.WindowWithTabs.Tab {
    return if (self.main_window.tabs_count > 1)
        &self.main_window.tabs[1]
    else
        null;
}

fn updateInventoryTab(self: *Self) !void {
    const tab = self.tabWithInventory();
    const selected_line = tab.window.selected_line orelse 0;
    tab.window.clearRetainingCapacity();
    var itr = self.inventory.items.iterator();
    while (itr.next()) |item_ptr| {
        var buffer: w.TextArea.Line = undefined;
        try tab.window.addOption(
            self.alloc,
            try self.formatInventoryLine(&buffer, item_ptr.*),
            item_ptr.*,
            useDropDescribe,
            describeSelectedItem,
        );
    }
    if (tab.window.options.items.len > 0) {
        try tab.window.selectLine(if (selected_line < tab.window.options.items.len)
            selected_line
        else
            tab.window.options.items.len - 1);
    }
}

const inventory_line_fmt = std.fmt.comptimePrint(
    "{{u}} {{s:<{d}}}{{s}}",
    .{w.WindowWithTabs.TAB_CONTENT_OPTIONS.region.cols - 7}, // "{u} ".len == 2 + "[ ]".len == 3 + 2 for pads
);

fn formatInventoryLine(self: *Self, line: *w.TextArea.Line, item: g.Entity) ![]const u8 {
    const sprite = self.session.registry.getUnsafe(item, c.Sprite);
    const name = if (self.session.registry.get(item, c.Description)) |desc|
        desc.name()
    else
        "???";
    const using = if (item.eql(self.equipment.weapon) or item.eql(self.equipment.light))
        "[x]"
    else if (self.session.isTool(item)) "[ ]" else "   ";
    log.debug("{d}: {u} {s} {s}", .{ item.id, sprite.codepoint, name, using });
    return try std.fmt.bufPrint(line, inventory_line_fmt, .{ sprite.codepoint, name, using });
}

fn useDropDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Buttons is helt. Show modal window for {any}", .{item});
    var window = w.OptionsWindow(g.Entity).init(self, .modal, "Cancel", "Choose");
    try window.addOption(self.alloc, "Use", item, useSelectedItem, null);
    try window.addOption(self.alloc, "Drop", item, dropSelectedItem, null);
    try window.addOption(self.alloc, "Describe", item, describeSelectedItem, null);
    self.actions_window = window;
}

fn takeFromPileOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var window = w.OptionsWindow(g.Entity).init(self, .modal, "Cancel", "Take");
    try window.addOption(self.alloc, "Take", item, takeSelectedItem, null);
    try window.addOption(self.alloc, "Describe", item, describeSelectedItem, null);
    self.actions_window = window;
}

fn useSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Use item {d} ({any})", .{ item.id, self.equipment });

    if (item.eql(self.equipment.weapon)) {
        self.equipment.weapon = null;
    } else if (self.session.registry.get(item, c.Weapon)) |_| {
        self.equipment.weapon = item;
    }
    if (item.eql(self.equipment.light)) {
        self.equipment.light = null;
    } else if (self.session.registry.get(item, c.SourceOfLight)) |_| {
        self.equipment.light = item;
    }
    try self.updateInventoryTab();
}

fn addDropTab(self: *Self, drop: g.Entity) !void {
    if (self.main_window.tabs_count < 2) {
        log.debug("Add drop tab for {any}", .{drop});
        self.main_window.addTab("Drop", "Close", "Choose");
    }
    try self.updateDropTab(drop);
}

fn updateDropTab(self: *Self, drop: g.Entity) !void {
    self.drop = drop;
    const tab = &self.main_window.tabs[1];
    const selected_line = tab.window.selected_line orelse 0;
    tab.window.clearRetainingCapacity();
    if (self.session.registry.get(drop, c.Pile)) |pile| {
        var itr = pile.items.iterator();
        while (itr.next()) |item_ptr| {
            try self.addDropOption(tab, item_ptr.*);
        }
    } else {
        try self.addDropOption(tab, drop);
    }
    if (tab.window.options.items.len > 0) {
        try tab.window.selectLine(if (selected_line < tab.window.options.items.len)
            selected_line
        else
            tab.window.options.items.len - 1);
    }
}

fn addDropOption(self: *Self, tab: *w.WindowWithTabs.Tab, item: g.Entity) !void {
    var buffer: w.TextArea.Line = undefined;
    const sprite = self.session.registry.getUnsafe(item, c.Sprite);
    const name = if (self.session.registry.get(item, c.Description)) |desc|
        desc.name()
    else
        "???";
    const label = try std.fmt.bufPrint(&buffer, "{u} {s}", .{ sprite.codepoint, name });
    try tab.window.addOption(self.alloc, label, item, takeFromPileOrDescribe, describeSelectedItem);
}

fn describeSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Show info about item {d}", .{item.id});
    self.description_window = try w.ModalWindow.initEntityDescription(
        self.alloc,
        self.session.registry,
        item,
        self.session.runtime.isDevMode(),
    );
}

/// Moves an item from the inventory to the player's position on the level.
/// Add the Drop tab
fn dropSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const place = self.session.level.playerPosition().place;
    log.debug("Drop item {d} at {any}", .{ item.id, place });

    std.debug.assert(self.inventory.items.remove(item));
    if (item.eql(self.equipment.weapon)) {
        self.equipment.weapon = null;
    }
    if (item.eql(self.equipment.light)) {
        self.equipment.light = null;
    }
    if (try self.session.level.addItemAtPlace(item, place)) |pile_entity| {
        try self.addDropTab(pile_entity);
    } else {
        try self.addDropTab(item);
    }
    try self.updateInventoryTab();
}

/// Moves entity from the pile to the inventory.
/// Removes the Pile tab if the item was the last in the pile.
fn takeSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.inventory.items.add(item);
    const entity = self.drop orelse @panic("Attempt to take an undefined item");
    if (self.session.registry.get(entity, c.Pile)) |pile| {
        _ = pile.items.remove(item);
        // Remove the pile only if it is became empty
        if (pile.items.size() == 0) {
            try self.session.registry.removeEntity(entity);
            self.main_window.removeLastTab(self.alloc);
            self.drop = null;
        } else {
            try self.updateDropTab(self.drop.?);
        }
    } else {
        std.debug.assert(entity.eql(item));
        try self.session.registry.remove(item, c.Position);
        try self.session.level.removeEntity(item);
        self.main_window.removeLastTab(self.alloc);
    }
    try self.updateInventoryTab();
}
