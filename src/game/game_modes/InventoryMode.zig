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
//! ║                     Close       Choose ║     ║                     Close       Choose ║
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
//! ║                     Cancel       Use   ║     ║                                 Close  ║
//! ╚════════════════════════════════════════╝     ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.inventory_mode);

const InventoryMode = @This();

const Tab = struct {
    title: []const u8,
    window: w.OptionsWindow(g.Entity),
    parent: *InventoryMode,
};

const InventoryOptions = enum { Use, Drop, Describe };
const PileOptions = enum { Take, Describe };

const bordered_region = w.TextArea.Options.full_screen.region;
const tab_content_options = blk: {
    var prototype = w.TextArea.Options.full_screen;
    // reserve one line for the title separator and one line for upper border
    prototype.region.top_left.row += 2;
    prototype.region.rows -= 3;
    // reserve two columns for border
    prototype.region.top_left.col += 1;
    prototype.region.cols -= 2;
    break :blk prototype;
};

alloc: std.mem.Allocator,
session: *g.GameSession,
inventory: *c.Inventory,
equipment: *c.Equipment,
/// The entity under the player's feet. Can be a pile or a single item
drop: ?g.Entity,
tabs: [2]Tab = undefined,
tabs_count: u8 = 0,
active_tab_idx: usize = 0,
description_window: ?w.DescriptionWindow = null,
actions_window: ?w.OptionsWindow(g.Entity) = null,

pub fn init(
    self: *InventoryMode,
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
    const tab = &self.tabs[0];
    self.tabs_count = 1;
    tab.* = .{
        .title = "Inventory",
        .window = w.OptionsWindow(g.Entity).init(tab, tab_content_options, "Close", "Choose"),
        .parent = self,
    };
    try self.updateInventoryTab(tab);

    if (drop) |item| {
        try self.addDropTab(item);
    }
    try self.draw();
}

// TODO use arena
pub fn deinit(self: *InventoryMode) void {
    if (self.description_window) |*window| {
        window.deinit(self.alloc);
    }
    if (self.actions_window) |*window| {
        window.deinit(self.alloc);
    }
    for (&self.tabs) |*tab| tab.window.deinit(self.alloc);
    self.tabs_count = 0;
}

pub fn tick(self: *InventoryMode) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.description_window) |*window| {
            if (try window.handleButton(btn)) {
                std.log.debug("Close description window", .{});
                try window.close(self.alloc, self.session.render);
                self.description_window = null;
            }
        } else if (self.actions_window) |*window| {
            switch (try window.handleButton(btn)) {
                .close_btn, .choose_btn => {
                    std.log.debug("Close actions window", .{});
                    try window.close(self.alloc, self.session.render);
                    self.actions_window = null;
                },
                else => {},
            }
        } else {
            switch (btn.game_button) {
                .left => if (self.active_tab_idx > 0) {
                    self.active_tab_idx -= 1;
                },
                .right => if (self.active_tab_idx < self.tabs_count - 1) {
                    self.active_tab_idx += 1;
                },
                else => switch (try self.tabs[self.active_tab_idx].window.handleButton(btn)) {
                    .close_btn => {
                        try self.session.play(null);
                        return;
                    },
                    else => {},
                },
            }
        }
        try self.draw();
    }
}

fn draw(self: *InventoryMode) !void {
    if (self.description_window) |*window| {
        log.debug("Draw description window", .{});
        try window.draw(self.session.render);
    } else if (self.actions_window) |*window| {
        log.debug("Draw actions window", .{});
        try window.draw(self.session.render);
    } else {
        log.debug("Draw tab window {d}", .{self.active_tab_idx});
        try self.tabs[self.active_tab_idx].window.draw(self.session.render);
        const tab_title_width: u8 = @intCast((bordered_region.cols - 2) / self.tabs_count);
        try self.session.render.drawDoubledBorder(bordered_region);
        try self.session.render.drawHorizontalLine(
            '═',
            bordered_region.top_left.movedToNTimes(.down, 2).movedTo(.right),
            bordered_region.cols - 2,
        );
        for (self.tabs[0..self.tabs_count], 0..) |tab, idx| {
            const cursor = bordered_region.top_left
                .movedTo(.down)
                .movedToNTimes(.right, @intCast(1 + idx * tab_title_width));
            try self.session.render.drawTextWithAlign(
                tab_title_width,
                tab.title,
                cursor,
                .normal,
                .center,
            );
        }
        // Draw a border around the active tab
        const cursor = bordered_region.top_left
            .movedTo(.down)
            .movedToNTimes(.right, @intCast(self.active_tab_idx * tab_title_width));
        const cursor_above = cursor.movedTo(.up);
        const underline_cursor = cursor.movedTo(.down);
        try self.session.render.drawSymbol('╔', cursor_above, .normal);
        try self.session.render.drawSymbol('╗', cursor_above.movedToNTimes(.right, tab_title_width + 1), .normal);

        try self.session.render.drawSymbol('║', cursor, .normal);
        try self.session.render.drawSymbol('║', cursor.movedToNTimes(.right, tab_title_width + 1), .normal);

        try self.session.render.drawHorizontalLine(' ', underline_cursor, tab_title_width + 1);
        try self.session.render.drawSymbol(
            if (self.active_tab_idx > 0) '╝' else '║',
            underline_cursor,
            .normal,
        );
        try self.session.render.drawSymbol(
            if (self.active_tab_idx < self.tabs_count - 1) '╚' else '║',
            underline_cursor.movedToNTimes(.right, tab_title_width + 1),
            .normal,
        );
    }
}

fn updateInventoryTab(self: *InventoryMode, tab: *Tab) !void {
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
    .{tab_content_options.maxLineSymbols() - 5}, // "{u} ".len == 2 + "[ ]".len == 3
);

fn formatInventoryLine(self: *InventoryMode, line: *w.TextArea.Line, item: g.Entity) ![]const u8 {
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
    const tab: *Tab = @ptrCast(@alignCast(ptr));
    log.debug("Buttons is helt. Show modal window for {any}", .{item});
    const alloc = tab.parent.alloc;
    var window = w.OptionsWindow(g.Entity).init(tab, .modal, "Cancel", "Use");
    window.above_scene = false;
    try window.addOption(alloc, "Use", item, useSelectedItem, null);
    try window.addOption(alloc, "Drop", item, dropSelectedItem, null);
    try window.addOption(alloc, "Describe", item, describeSelectedItem, null);
    tab.parent.actions_window = window;
}

fn takeFromPileOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const tab: *Tab = @ptrCast(@alignCast(ptr));
    const alloc = tab.parent.alloc;
    var window = w.OptionsWindow(g.Entity).init(tab, .modal, "Cancel", "Take");
    try window.addOption(alloc, "Take", item, takeSelectedItem, null);
    try window.addOption(alloc, "Describe", item, describeSelectedItem, null);
    tab.parent.actions_window = window;
}

fn useSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const tab: *Tab = @ptrCast(@alignCast(ptr));
    const self = tab.parent;
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
    try self.updateInventoryTab(tab);
}

/// Moves an item from the inventory to the player's position on the level.
/// Add the Drop tab
fn dropSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const tab: *Tab = @ptrCast(@alignCast(ptr));
    const self = tab.parent;
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
    try self.updateInventoryTab(tab);
}

fn addDropTab(self: *InventoryMode, drop: g.Entity) !void {
    log.debug("Add drop tab for {any}", .{drop});
    self.drop = drop;
    self.tabs_count = 2;
    const tab = &self.tabs[1];
    tab.* = .{
        .title = "Drop",
        .window = w.OptionsWindow(g.Entity).init(tab, tab_content_options, "Close", "Choose"),
        .parent = self,
    };
    try self.updateDropTab(tab, drop);
}

fn updateDropTab(self: *InventoryMode, tab: *Tab, drop: g.Entity) !void {
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

fn addDropOption(self: *InventoryMode, tab: *Tab, item: g.Entity) !void {
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
    const tab: *Tab = @ptrCast(@alignCast(ptr));
    const self = tab.parent;
    log.debug("Show info about item {d}", .{item.id});
    self.description_window = try w.DescriptionWindow.init(
        self.alloc,
        self.session.registry,
        item,
        self.session.runtime.isDevMode(),
    );
}

/// Moves entity id of an item from the pile to the inventory.
/// Removes the Pile tab if the item was the last in the pile.
fn takeSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const tab: *Tab = @ptrCast(@alignCast(ptr));
    const self = tab.parent;
    try self.inventory.items.add(item);
    const entity = self.drop orelse @panic("Attempt to take an item when dropped item is not defined");
    if (self.session.registry.get(entity, c.Pile)) |pile| {
        _ = pile.items.remove(item);
        // Remove the pile only if it is became empty
        if (pile.items.size() == 0) {
            try self.session.registry.removeEntity(entity);
            self.tabs_count = 1;
            self.active_tab_idx = 0;
            self.drop = null;
        } else {
            try self.updateDropTab(tab, self.drop.?);
        }
    } else {
        std.debug.assert(entity.eql(item));
        self.tabs_count = 1;
        self.active_tab_idx = 0;
        self.drop = null;
    }
    try self.updateInventoryTab(&self.tabs[0]);
}
