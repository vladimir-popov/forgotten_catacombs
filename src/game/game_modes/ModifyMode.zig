//! In this mode the player can pay to somebody to recognize an unknown item,
//! or modify its equipment.
//! ```
//! ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║
//! ║ ║   Recognize     ║       Modify      ║║
//! ║╔╝                 ╚═══════════════════║║
//! ║║░\░Club░░░░░░░░░░░░░░░░░░░░░░░░░░100$░║║
//! ║║ { Bow                           200$ ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║╚══════════════════════════════════════╝║
//! ║════════════════════════════════════════║
//! ║    000$             Close       Choose ║
//! ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.modify_mode);

const MODAL_WINDOW_REGION: p.Region = p.Region.init(2, 2, g.DISPLAY_ROWS - 4, g.DISPLAY_COLS - 2);
const BASE_MODIFICATION_PRICE = 100;
const RECOGNITION_PRICE = 100;

const Self = @This();

alloc: std.mem.Allocator,
session: *g.GameSession,
inventory: *c.Inventory,
wallet: *c.Wallet,
main_window: w.WindowWithTabs = .{},
/// Contains an entity description, or a notification.
modal_window: ?w.ModalWindow(w.TextArea) = null,
/// Contains available actions
actions_window: ?w.ModalWindow(w.OptionsArea(g.Entity)) = null,

pub fn init(
    self: *Self,
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    inventory: *c.Inventory,
    wallet: *c.Wallet,
) !void {
    self.* = .{
        .alloc = alloc,
        .session = session,
        .inventory = inventory,
        .wallet = wallet,
    };
    self.main_window.addTab("Recognize", self);
    self.main_window.addTab("Modify", self);
    try self.updateTabs();
    try self.draw();
}

pub fn deinit(self: *Self) void {
    if (self.modal_window) |*window| {
        window.deinit(self.alloc);
    }
    if (self.actions_window) |*window| {
        window.deinit(self.alloc);
    }
    self.main_window.deinit(self.alloc);
}

pub fn tick(self: *Self) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.modal_window) |*window| {
            if (try window.handleButton(btn)) {
                log.debug("Close modal window", .{});
                try window.hide(self.session.render, .fill_region);
                window.deinit(self.alloc);
                self.modal_window = null;
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
                try self.session.continuePlay(null, null);
                return;
            }
        }
        try self.draw();
    }
}

inline fn tabRecognize(self: *Self) *w.WindowWithTabs.Tab {
    return &self.main_window.tabs[0];
}

inline fn tabModify(self: *Self) *w.WindowWithTabs.Tab {
    return &self.main_window.tabs[1];
}

pub fn updateTabs(self: *Self) !void {
    const active_tab = self.main_window.activeTab();
    const selected_line = active_tab.area.content.selected_line;

    self.tabRecognize().area.content.clearRetainingCapacity();
    self.tabModify().area.content.clearRetainingCapacity();
    var itr = self.inventory.items.iterator();
    while (itr.next()) |item_ptr| {
        const item = item_ptr.*;
        var buffer: w.TextArea.Line = undefined;
        if (self.session.journal.isKnown(item)) {
            if (self.canBeModified(item)) {
                const price = self.calculateModificationPrice(item);
                try self.tabModify().area.content.addOption(
                    self.alloc,
                    try self.formatLine(&buffer, item, price),
                    item,
                    modifyDescribe,
                    describeItem,
                );
            }
        } else {
            try self.tabRecognize().area.content.addOption(
                self.alloc,
                try self.formatLine(&buffer, item, RECOGNITION_PRICE),
                item,
                recognizeDescribe,
                describeItem,
            );
        }
    }
    if (active_tab.area.content.options.items.len > 0) {
        try active_tab.area.content.selectLine(
            if (selected_line < active_tab.area.content.options.items.len)
                selected_line
            else
                active_tab.area.content.options.items.len - 1,
        );
    }
}

const line_fmt = std.fmt.comptimePrint(
    "{{s:<{d}}}{{d:4}}$",
    .{w.WindowWithTabs.CONTENT_AREA_REGION.cols - 7}, // "0000$".len == 5 + 2 for pads
);

fn formatLine(self: *Self, line: *w.TextArea.Line, item: g.Entity, price: u16) ![]const u8 {
    const description = self.session.registry.getUnsafe(item, c.Description);
    const name = g.presets.Descriptions.get(description.preset).name;
    log.debug("fromat line: {d}: {u}({d}) {s} {s}", .{ item.id, name, price });
    return try std.fmt.bufPrint(line, line_fmt, .{ name, price });
}

fn calculateModificationPrice(self: Self, item: g.Entity) u16 {
    var price: u16 = BASE_MODIFICATION_PRICE;
    if (self.session.registry.get(item, c.Rarity)) |rarity| {
        switch (rarity.*) {
            .rare => price = 1.5 * BASE_MODIFICATION_PRICE,
            .very_rare => price *|= 2,
            .legendary => price *|= 3,
            .unique => price *|= 5,
            else => {},
        }
    }
    if (self.session.registry.get(item, c.Modification)) |modification| {
        var itr = modification.modificators.iterator();
        while (itr.next()) |entry| {
            if (entry.value.* != 0)
                price +|= BASE_MODIFICATION_PRICE;
        }
    }
    return price;
}

inline fn canBeModified(self: *Self, item: g.Entity) bool {
    return switch (g.meta.entityType(&self.session.registry, item)) {
        .weapon, .armor => true,
        else => false,
    };
}

fn recognizeDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var area = w.OptionsArea(g.Entity).center(self);
    try area.addOption(self.alloc, "Recognize", item, recognizeItem, null);
    try area.addOption(self.alloc, "Describe", item, describeItem, null);
    self.actions_window = .init(area, MODAL_WINDOW_REGION);
}

fn recognizeItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    switch (g.meta.entityType(&self.session.registry, item)) {
        .weapon => try self.session.journal.markWeaponAsKnown(item),
        .armor => try self.session.journal.markArmorAsKnown(item),
        .potion => if (g.meta.getPotionType(&self.session.registry, item)) |potion_type| {
            try self.session.journal.markPotionAsKnown(potion_type);
        },
        else => |t| {
            std.debug.panic("Entity {d} with type {t} can't be recognized", .{ item.id, t });
        },
    }
    try self.updateTabs();
}

fn modifyDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var area = w.OptionsArea(g.Entity).center(self);
    try area.addOption(self.alloc, "Modify", item, modifyItem, null);
    try area.addOption(self.alloc, "Describe", item, describeItem, null);
    self.actions_window = .init(area, MODAL_WINDOW_REGION);
}

fn modifyItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var prng = std.Random.DefaultPrng.init(self.session.seed);
    switch (g.meta.entityType(&self.session.registry, item)) {
        .weapon => {
            try g.meta.modifyWeapon(&self.session.registry, prng.random(), item, 1, 5);
            try self.session.journal.forgetWeapon(item);
        },
        // TODO: Modify an armor
        else => |t| {
            std.debug.panic("Entity {d} with type {t} can't be modified", .{ item.id, t });
        },
    }
}

fn describeItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Show info about item {d}", .{item.id});
    self.modal_window = try w.entityDescription(.{
        .alloc = self.alloc,
        .session = self.session,
        .entity = item,
        .max_region = MODAL_WINDOW_REGION,
    });
}

fn draw(self: *Self) !void {
    if (self.modal_window) |*window| {
        log.debug("Draw the modal window", .{});
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
