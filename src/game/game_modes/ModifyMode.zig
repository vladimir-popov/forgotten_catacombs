//! In this mode the player can pay to somebody to recognize an unknown item,
//! or modify its equipment.
//! ```
//! ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║
//! ║ ║   Recognize     ║       Modify      ║║
//! ║╔╝                 ╚═══════════════════║║
//! ║║░\░Club░░░░░░░░░░░░░░░░░░░░░░░░░░100$░║║
//! ║║ { Bow                           100$ ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║╚══════════════════════════════════════╝║
//! ║════════════════════════════════════════║
//! ║    000$             Close       Choose ║
//! ╚════════════════════════════════════════╝
//! ╔════════════════════════════════════════╗ ╔════════════════════════════════════════╗ ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║ ║ ╔═════════════════╔═══════════════════╗║ ║ ╔═════════════════╗═══════════════════╗║
//! ║ ║   Recognize     ║       Modify      ║║ ║ ║   Recognize     ║       Modify      ║║ ║ ║   Recognize     ║       Modify      ║║
//! ║╔╝═════════════════╝                   ║║ ║╔╝═════════════════╝                   ║║ ║╔╝═════════════════╝                   ║║
//! ║║░\░Club░░░░░░░░░░░░░░░░░░░░░░░░░░100$░║║ ║║ ┌───────────────────────────────────┐║║ ║║ ┌───────────────────────────────────┐║║
//! ║║ { Bow                           100$ ║║ ║║ │        Describe the item          │║║ ║║ │            Physic                 │║║
//! ║║                                      ║║ ║║ │        Modify somehow    x1       │║║ ║║ │             Fire                  │║║
//! ║║                                      ║║ ║║ │        Modify carefully  x2       │║║ ║║ │             Acid                  │║║
//! ║║                                      ║║ ║║ │        Modify manually   x3       │║║ ║║ │            Poison                 │║║
//! ║║                                      ║║ ║║ │              Help                 │║║ ║║ └───────────────────────────────────┘║║
//! ║║                                      ║║ ║║ └───────────────────────────────────┘║║ ║║                                      ║║
//! ║╚══════════════════════════════════════╝║ ║╚══════════════════════════════════════╝║ ║╚══════════════════════════════════════╝║
//! ║════════════════════════════════════════║ ║════════════════════════════════════════║ ║════════════════════════════════════════║
//! ║    000$             Close       Choose ║ ║    000$             Close       Choose ║ ║    000$             Close       Choose ║
//! ╚════════════════════════════════════════╝ ╚════════════════════════════════════════╝ ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.modify_mode);

const MODAL_WINDOW_REGION: p.Region = p.Region.init(3, 2, g.DISPLAY_ROWS - 5, g.DISPLAY_COLS - 2);
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
                try self.main_window.draw(self.session.render);
                window.deinit(self.alloc);
                self.modal_window = null;
            }
        } else if (self.actions_window) |*window| {
            if (try window.handleButton(btn)) {
                log.debug("Close actions window", .{});
                try self.main_window.draw(self.session.render);
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
    const selected_line = active_tab.scrollable_area.content.selected_line;

    self.tabRecognize().scrollable_area.content.clearRetainingCapacity();
    self.tabModify().scrollable_area.content.clearRetainingCapacity();
    var itr = self.inventory.items.iterator();
    while (itr.next()) |item_ptr| {
        const item = item_ptr.*;
        var buffer: [w.WindowWithTabs.CONTENT_AREA_REGION.cols + 4]u8 = undefined;
        if (self.session.journal.isKnown(item)) {
            if (self.canBeModified(item)) {
                const price = self.calculateBaseModificationPrice(item);
                try self.tabModify().scrollable_area.content.addOption(
                    self.alloc,
                    try self.formatLine(&buffer, item, price),
                    item,
                    modifyDescribe,
                    describeItem,
                );
            }
        } else {
            try self.tabRecognize().scrollable_area.content.addOption(
                self.alloc,
                try self.formatLine(&buffer, item, RECOGNITION_PRICE),
                item,
                recognizeDescribe,
                describeItem,
            );
        }
    }
    if (active_tab.scrollable_area.content.options.items.len > 0) {
        try active_tab.scrollable_area.content.selectLine(
            if (selected_line < active_tab.scrollable_area.content.options.items.len)
                selected_line
            else
                active_tab.scrollable_area.content.options.items.len - 1,
        );
    }
}

const line_fmt = std.fmt.comptimePrint(
    "{{u}} {{s:<{d}}}{{d:4}}$",
    .{w.WindowWithTabs.CONTENT_AREA_REGION.cols - 8}, // "{u} ".len == 2 + "0000$".len == 5 + 1 for the right pad
);

fn formatLine(self: *Self, buffer: []u8, item: g.Entity, price: u16) ![]const u8 {
    const sprite = self.session.registry.getUnsafe(item, c.Sprite);
    var name_buf: [24]u8 = undefined;
    const name = try g.descriptions.printName(&name_buf, self.session.journal, item);
    return try std.fmt.bufPrint(buffer, line_fmt, .{ sprite.codepoint, name, price });
}

fn calculateBaseModificationPrice(self: Self, item: g.Entity) u16 {
    const BASE_MODIFICATION_PRICE = 100;
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
    return self.session.registry.has(item, c.Weapon) or self.session.registry.has(item, c.Protection);
}

fn recognizeDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var area = w.OptionsArea(g.Entity).centered(self);
    try area.addOption(self.alloc, "Recognize", item, recognizeItem, null);
    try area.addOption(self.alloc, "Describe", item, describeItem, null);
    self.actions_window = .modalWindow(area, MODAL_WINDOW_REGION);
    // keep the main window opened
    return false;
}

fn recognizeItem(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const wallet = self.session.registry.getUnsafe(self.session.player, c.Wallet);
    if (wallet.money >= RECOGNITION_PRICE) {
        if (self.session.registry.has(item, c.Weapon))
            try self.session.journal.markWeaponAsKnown(item)
        else if (self.session.registry.has(item, c.Protection))
            try self.session.journal.markArmorAsKnown(item)
        else if (g.meta.getPotionType(&self.session.registry, item)) |potion_type|
            try self.session.journal.markPotionAsKnown(potion_type);

        wallet.money -= RECOGNITION_PRICE;
        try self.updateTabs();
    } else {
        self.modal_window = try w.notification(
            self.alloc,
            "You have not enough\nmoney.",
            .{ .max_region = MODAL_WINDOW_REGION },
        );
    }
    return true;
}

fn modifyDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var area = w.OptionsArea(g.Entity).centered(self);
    try area.addOption(self.alloc, "Describe the item", item, describeItem, null);
    try area.addOption(self.alloc, " Modify somehow   x1$", item, modifySomehow, null);
    try area.addOption(self.alloc, " Modify carefully x2$", item, modifyCarefully, null);
    try area.addOption(self.alloc, " Modify manually  x3$", item, modifyManually, null);
    try area.addOption(self.alloc, "Help", item, showHelp, null);
    self.actions_window = .modalWindow(area, MODAL_WINDOW_REGION);
    // keep the main window opened
    return false;
}

fn showHelp(ptr: *anyopaque, _: usize, _: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.modal_window = try w.notification(
        self.alloc,
        \\The  damage of  the chosen weapon
        \\or  the  protection  provided  by  
        \\armor will be altered. The  final 
        \\outcome     depends    on     how
        \\carefully  the   modification  is 
        \\performed.
        \\
        \\An arbitrary  modification  has a 
        \\50%    chance  of  worsening  the 
        \\effect.
        \\
        \\A  careful  modification  reduces 
        \\this risk to 10%.
        \\
        \\A manual modification allows  you  
        \\to  choose  the  specific  effect 
        \\that is guaranteed to be improved
        \\
        \\Every   additional   modification 
        \\makes the next one more expensive
    ,
        .{ .title = "Help", .max_region = MODAL_WINDOW_REGION, .text_align = .left },
    );
    return false;
}

fn modifySomehow(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.modify(item, 50, null, self.calculateBaseModificationPrice(item));
    return true;
}

fn modifyCarefully(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.modify(item, 10, null, 2 * self.calculateBaseModificationPrice(item));
    return true;
}
fn modifyManually(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const options = &self.actions_window.?.scrollable_area.content;
    log.debug("Show the list of possible effects", .{});
    options.clearRetainingCapacity();
    for (0..c.Effects.TypesCount) |idx| {
        const effect_type: c.Effects.Type = @enumFromInt(idx);
        if (effect_type == .heal) continue;
        try options.addOption(self.alloc, @tagName(effect_type), item, modifyManuallyEffect, null);
    }
    // Do not close the action_window, because we recreate it here
    return false;
}

fn modifyManuallyEffect(ptr: *anyopaque, idx: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const effect_type: c.Effects.Type = @enumFromInt(idx);
    try self.modify(item, 0, effect_type, 3 * self.calculateBaseModificationPrice(item));
    return true;
}

fn modify(self: *Self, item: g.Entity, worsen_chance: u8, effect_type: ?c.Effects.Type, price: u16) !void {
    const wallet = self.session.registry.getUnsafe(self.session.player, c.Wallet);
    if (wallet.money >= price) {
        var prng = std.Random.DefaultPrng.init(self.session.seed);
        const rand = prng.random();
        const range: p.Range(i8) = if (worsen_chance > 0 and rand.uintAtMost(u8, 100) < worsen_chance)
            .range(-5, -1)
        else
            .range(1, 5);
        if (self.session.registry.has(item, c.Weapon)) {
            try g.meta.modifyWeapon(&self.session.registry, prng.random(), item, range.min, range.max, effect_type);
            try self.session.journal.forgetWeapon(item);
        }
        wallet.money -= price;
        // TODO: Modify an armor
        try self.updateTabs();
    } else {
        self.modal_window = try w.notification(
            self.alloc,
            "You have not enough\nmoney.",
            .{ .max_region = MODAL_WINDOW_REGION },
        );
    }
}

fn describeItem(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Show info about item {d}", .{item.id});
    self.modal_window = try w.entityDescription(self.alloc, self.session, item);
    return false;
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
        var buf: [20]u8 = undefined;
        const money = self.session.registry.getUnsafe(self.session.player, c.Wallet).money;
        try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "Your money: {d:4}$", .{money}));
    }
}
