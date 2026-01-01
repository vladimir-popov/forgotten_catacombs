//! ```
//!                             The main window with two tabs:
//! ╔════════════════════════════════════════╗     ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║     ║╔══════════════════╔══════════════════╗ ║
//! ║ ║    Inventory    ║        Drop       ║║     ║║    Inventory     ║       Drop       ║ ║
//! ║╔╝                 ╚═══════════════════║║     ║║══════════════════╝                  ╚╗║
//! ║║░\░Club░░░░░░░░░░░░░░░░░░░░░░░weapon░░║║     ║║ % Apple                              ║║
//! ║║ ¡ Torch                       light  ║║     ║║                                      ║║
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

const MODAL_WINDOW_REGION: p.Region = p.Region.init(2, 2, g.DISPLAY_ROWS - 4, g.DISPLAY_COLS - 2);

const Self = @This();

alloc: std.mem.Allocator,
session: *g.GameSession,
inventory: *c.Inventory,
equipment: *c.Equipment,
/// The entity under the player's feet. Can be a pile or a single item
drop: ?g.Entity,
/// The action initiated during manage the inventory.
action: ?g.actions.Action = null,
main_window: w.WindowWithTabs = .{},
description_window: ?w.ModalWindow(w.TextArea) = null,
actions_window: ?w.ModalWindow(w.OptionsArea(g.Entity)) = null,

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
    };
    self.main_window.addTab("Inventory", self);
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
                log.debug("Close description window", .{});
                try window.hide(self.session.render, .fill_region);
                window.deinit(self.alloc);
                self.description_window = null;
            }
        } else if (self.actions_window) |*window| {
            if (try window.handleButton(btn)) {
                log.debug("Close actions window", .{});
                try window.hide(self.session.render, .fill_region);
                window.deinit(self.alloc);
                self.actions_window = null;
            }
        } else {
            if (try self.main_window.handleButton(btn)) {
                // the  deinit method will be invoked here:
                try self.session.continuePlay(null, self.action);
                return;
            }
        }
        try self.draw();
        if (self.action) |act| {
            try self.session.continuePlay(null, act);
            return;
        }
    }
}

fn draw(self: *Self) !void {
    if (self.description_window) |*window| {
        log.debug("Draw the description window", .{});
        try window.draw(self.session.render);
    } else if (self.actions_window) |*window| {
        log.debug("Draw the actions window", .{});
        try window.draw(self.session.render);
    } else {
        log.debug("Draw the main window tab {d}", .{self.main_window.active_tab_idx});
        try self.main_window.draw(self.session.render);
        var buf: [10]u8 = undefined;
        const money = self.session.registry.getUnsafe(self.session.player, c.Wallet).money;
        try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "{d}$", .{money}));
    }
}

inline fn tabWithInventory(self: *Self) *w.WindowWithTabs.Tab {
    return &self.main_window.tabs[0];
}

fn tabWithDrop(self: *Self) ?*w.WindowWithTabs.Tab {
    return if (self.main_window.tabs_count > 1)
        &self.main_window.tabs[1]
    else
        null;
}

pub fn updateInventoryTab(self: *Self) !void {
    const tab = self.tabWithInventory();
    const selected_line = tab.area.content.selected_line;
    tab.area.content.clearRetainingCapacity();
    var itr = self.inventory.items.iterator();
    while (itr.next()) |item_ptr| {
        var buffer: w.TextArea.Line = undefined;
        try tab.area.content.addOption(
            self.alloc,
            try self.formatInventoryLine(&buffer, item_ptr.*),
            item_ptr.*,
            useDropDescribe,
            describeSelectedItem,
        );
    }
    if (tab.area.content.options.items.len > 0) {
        try tab.area.content.selectLine(if (selected_line < tab.area.content.options.items.len)
            selected_line
        else
            tab.area.content.options.items.len - 1);
    }
}

const inventory_line_fmt = std.fmt.comptimePrint(
    "{{u}} {{s:<{d}}}{{s}}",
    .{w.WindowWithTabs.CONTENT_AREA_REGION.cols - 10}, // "{u} ".len == 2 + "light weapon".len == 6 + 2 for pads
);

fn formatInventoryLine(self: *Self, line: *w.TextArea.Line, item: g.Entity) ![]const u8 {
    const sprite = self.session.registry.getUnsafe(item, c.Sprite);
    var buf: [32]u8 = undefined;
    const name = try g.descriptions.printName(&buf, self.session.journal, item);
    const using = if (item.eql(self.equipment.weapon))
        "weapon"
    else if (item.eql(self.equipment.light))
        " light"
    else if (item.eql(self.equipment.ammunition))
        "  ammo"
    else
        "      ";
    log.debug("fromat line: {d}: {u}({d}) {s} {s}", .{ item.id, sprite.codepoint, sprite.codepoint, name, using });
    return try std.fmt.bufPrint(line, inventory_line_fmt, .{ sprite.codepoint, name, using });
}

fn useDropDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Buttons is helt. Show modal window for {any}", .{item});
    var area = w.OptionsArea(g.Entity).center(self);
    if (item.eql(self.equipment.light) or item.eql(self.equipment.weapon)) {
        try area.addOption(self.alloc, "Unequip", item, unequipItem, null);
    } else {
        switch (g.meta.entityType(&self.session.registry, item)) {
            .weapon => try area.addOption(self.alloc, "Use as a weapon", item, useAsWeapon, null),
            .ammunition => try area.addOption(self.alloc, "Put to quiver", item, putToQuiver, null),
            .armor => try area.addOption(self.alloc, "Equip", item, useAsArmor, null),
            .light => try area.addOption(self.alloc, "Use as a light", item, useAsLight, null),
            .potion => try area.addOption(self.alloc, "Drink", item, consumeItem, null),
            .food => try area.addOption(self.alloc, "Eat", item, consumeItem, null),
            .enemy => {
                log.err("Attempt to use an enemy {d}", .{item.id});
            },
        }
    }
    try area.addOption(self.alloc, "Drop", item, dropSelectedItem, null);
    try area.addOption(self.alloc, "Describe", item, describeSelectedItem, null);
    self.actions_window = .init(area, MODAL_WINDOW_REGION);
}

fn unequipItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Unequip the item {d}. (current equipment: {any})", .{ item.id, self.equipment });
    if (item.eql(self.equipment.light))
        self.equipment.light = null;
    if (item.eql(self.equipment.weapon))
        self.equipment.weapon = null;
    if (item.eql(self.equipment.ammunition))
        self.equipment.ammunition = null;

    try self.updateInventoryTab();
}

fn useAsLight(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Use the item {d} as a source of light. (current equipment: {any})", .{ item.id, self.equipment });
    self.equipment.light = item;
    try self.updateInventoryTab();
}

fn useAsWeapon(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Use the item {d} as weapon. (current equipment: {any})", .{ item.id, self.equipment });
    self.equipment.weapon = item;
    if (self.equipment.light == null) {
        if (self.session.registry.get(item, c.SourceOfLight)) |_| {
            self.equipment.light = item;
        }
    }

    try self.updateInventoryTab();
}

fn useAsArmor(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Use the item {d} as armor. (current equipment: {any})", .{ item.id, self.equipment });
    self.equipment.armor = item;
    try self.updateInventoryTab();
}

fn putToQuiver(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Use the item {d} as an ammunition. (current equipment: {any})", .{ item.id, self.equipment });
    self.equipment.ammunition = item;
    try self.updateInventoryTab();
}

fn consumeItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (self.session.registry.get(item, c.Consumable)) |consumable| {
        log.debug("Consume the item {d} {any}. (current equipment: {any})", .{ item.id, consumable, self.equipment });
        switch (consumable.consumable_type) {
            .potion => {
                self.action = .{ .drink = item };
            },
            .food => {
                self.action = .{ .eat = item };
            },
        }
        _ = self.inventory.items.remove(item);
    }
    try self.updateInventoryTab();
}

fn takeFromPileOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var area = w.OptionsArea(g.Entity).center(self);
    try area.addOption(self.alloc, "Take", item, takeSelectedItem, null);
    try area.addOption(self.alloc, "Describe", item, describeSelectedItem, null);
    self.actions_window = .init(area, MODAL_WINDOW_REGION);
}

fn addDropTab(self: *Self, drop: g.Entity) !void {
    if (self.main_window.tabs_count < 2) {
        log.debug("Add drop tab for {any}", .{drop});
        self.main_window.addTab("Drop", self);
    }
    try self.updateDropTab(drop);
}

fn updateDropTab(self: *Self, drop: g.Entity) !void {
    self.drop = drop;
    const tab = &self.main_window.tabs[1];
    const selected_line = tab.area.content.selected_line;
    tab.area.content.clearRetainingCapacity();
    if (self.session.registry.get(drop, c.Pile)) |pile| {
        var itr = pile.items.iterator();
        while (itr.next()) |item_ptr| {
            try self.addDropOption(tab, item_ptr.*);
        }
    } else {
        try self.addDropOption(tab, drop);
    }
    if (tab.area.content.options.items.len > 0) {
        try tab.area.content.selectLine(if (selected_line < tab.area.content.options.items.len)
            selected_line
        else
            tab.area.content.options.items.len - 1);
    }
}

fn addDropOption(self: *Self, tab: *w.WindowWithTabs.Tab, item: g.Entity) !void {
    var buffer: w.TextArea.Line = undefined;
    var len = (try std.fmt.bufPrint(&buffer, "{u} ", .{self.session.registry.getUnsafe(item, c.Sprite).codepoint})).len;
    len += (try g.descriptions.printName(buffer[len..], self.session.journal, item)).len;
    try tab.area.content.addOption(self.alloc, buffer[0..len], item, takeFromPileOrDescribe, describeSelectedItem);
}

fn describeSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Show info about item {d}", .{item.id});
    self.description_window = try w.entityDescription(.{
        .alloc = self.alloc,
        .session = self.session,
        .entity = item,
        .max_region = MODAL_WINDOW_REGION,
    });
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
