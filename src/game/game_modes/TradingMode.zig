//! ```
//!                             The main window with two tabs:
//! ╔════════════════════════════════════════╗     ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║     ║╔══════════════════╔══════════════════╗ ║
//! ║ ║       Buy       ║        Sell       ║║     ║║        Buy       ║       Sell       ║ ║
//! ║╔╝                 ╚═══════════════════║║     ║║══════════════════╝                  ╚╗║
//! ║║░\░Club░░░░░░░░░░░░░░░░░░░░░░░░░░░30$░║║     ║║ / Torch                         122$ ║║
//! ║║   Apple                          43$ ║║     ║║                                      ║║
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
//! ║ ║       Buy        ║        Sell      ║║     ║ ║        Buy       ║        Sell      ║║
//! ║╔╝                  ╚══════════════════║║     ║╔╝                  ╚══════════════════║║
//! ║║                                      ║║     ║║                                      ║║
//! ║║ ┌───────────────────────────────────┐║║     ║║ ┌────────────────Club───────────────┐║║
//! ║║ │Buy                                │║║     ║║ │ Price: 30$                        │║║
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

const log = std.log.scoped(.trading_mode);

/// The biggest region that can be occupied by a modal window with description
const MODAL_WINDOW_REGION: p.Region = p.Region.init(3, 2, g.DISPLAY_ROWS - 5, g.DISPLAY_COLS - 2);

const Self = @This();

alloc: std.mem.Allocator,
session: *g.GameSession,
wallet: *c.Wallet,
inventory: *c.Inventory,
shop: *c.Shop,
main_window: w.WindowWithTabs = .{},
/// Contains an entity description, or a notification.
modal_window: ?w.ModalWindow(w.TextArea) = null,
/// Contains available actions
actions_window: ?w.ModalWindow(w.OptionsArea(g.Entity)) = null,

pub fn init(
    self: *Self,
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    shop: *c.Shop,
) !void {
    self.* = .{
        .alloc = alloc,
        .session = session,
        .wallet = session.registry.getUnsafe(session.player, c.Wallet),
        .inventory = session.registry.getUnsafe(session.player, c.Inventory),
        .shop = shop,
    };
    self.main_window.addTab("Buy", self);
    try self.updateBuyingTab();

    self.main_window.addTab("Sell", self);
    try self.updateSellingTab();

    try self.draw();
}

// TODO use arena
pub fn deinit(self: *Self) void {
    if (self.modal_window) |*window| {
        window.deinit(self.alloc);
    }
    if (self.actions_window) |*window| {
        window.deinit(self.alloc);
    }
    self.main_window.deinit(self.alloc);
}

inline fn buyingTab(self: *Self) *w.WindowWithTabs.Tab {
    return &self.main_window.tabs[0];
}

inline fn sellingTab(self: *Self) *w.WindowWithTabs.Tab {
    return &self.main_window.tabs[1];
}

pub fn tick(self: *Self) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.modal_window) |*window| {
            if (try window.handleButton(btn)) {
                std.log.debug("Close description window", .{});
                try self.main_window.draw(self.session.render);
                window.deinit(self.alloc);
                self.modal_window = null;
            }
        } else if (self.actions_window) |*window| {
            if (try window.handleButton(btn)) {
                std.log.debug("Close actions window", .{});
                try self.main_window.draw(self.session.render);
                window.deinit(self.alloc);
                self.actions_window = null;
            }
        } else {
            if (try self.main_window.handleButton(btn)) {
                try self.session.continuePlay(null, null);
                return;
            }
        }
        try self.draw();
    }
    if (self.session.runtime.popCheat()) |cheat| {
        log.debug("Run cheat {any}", .{cheat});
        switch (cheat) {
            .set_money => |money| {
                if (self.main_window.active_tab_idx == 0) {
                    self.shop.balance = money;
                } else {
                    self.wallet.money = money;
                }
                try self.drawBalance();
            },
            else => {
                log.warn("The cheat {any} is ignored in trading mode.", .{cheat});
            },
        }
    }
}

fn draw(self: *Self) !void {
    if (self.modal_window) |*window| {
        log.debug("Draw description window", .{});
        try window.draw(self.session.render);
    } else if (self.actions_window) |*window| {
        log.debug("Draw actions window", .{});
        try window.draw(self.session.render);
    } else {
        log.debug("Draw main window tab {d}", .{self.main_window.active_tab_idx});
        try self.main_window.draw(self.session.render);
        try self.drawBalance();
    }
}

fn drawBalance(self: Self) !void {
    var buf: [30]u8 = undefined;
    if (self.main_window.active_tab_idx == 1) {
        try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "Traider's:  {d:4}$", .{self.shop.balance}));
    } else {
        try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "Your money: {d:4}$", .{self.wallet.money}));
    }
}

const product_fmt = std.fmt.comptimePrint(
    "{{u}} {{s:<{d}}}{{d:4}}$",
    .{w.WindowWithTabs.CONTENT_AREA_REGION.cols - 9}, // "{u} ".len == 2 + "0000$".len == 5 + 2 for pads
);

fn formatProduct(self: *Self, line: *w.TextArea.Line, item: g.Entity, for_buying: bool) ![]const u8 {
    if (self.session.registry.get2(item, c.Price, c.Sprite)) |tuple| {
        const price, const sprite = tuple;
        var buf: [16]u8 = undefined;
        const name = try g.meta.printName(&buf, self.session.journal, item);
        return try std.fmt.bufPrint(
            line,
            product_fmt,
            .{ sprite.codepoint, name, self.actualPrice(price, for_buying) },
        );
    } else {
        std.debug.panic("Error on format product. Some component was not found", .{});
    }
}

fn actualPrice(self: Self, price: *const c.Price, for_buying: bool) u16 {
    const base_price: f16 = @floatFromInt(price.value);
    return if (for_buying)
        @intFromFloat(base_price * self.shop.price_multiplier)
    else
        @intFromFloat(base_price / self.shop.price_multiplier);
}

fn updateBuyingTab(self: *Self) !void {
    const tab = self.buyingTab();
    const selected_line = tab.scrollable_area.content.selected_line;
    tab.scrollable_area.content.clearRetainingCapacity();
    var itr = self.shop.items.iterator();
    while (itr.next()) |item_ptr| {
        var buffer: w.TextArea.Line = undefined;
        try tab.scrollable_area.content.addOption(
            self.alloc,
            try self.formatProduct(&buffer, item_ptr.*, true),
            item_ptr.*,
            buyOrDescribe,
            describeSelectedItem,
        );
    }
    if (tab.scrollable_area.content.options.items.len > 0) {
        try tab.scrollable_area.content.selectLine(if (selected_line < tab.scrollable_area.content.options.items.len)
            selected_line
        else
            tab.scrollable_area.content.options.items.len - 1);
    }
}

fn updateSellingTab(self: *Self) !void {
    const tab = self.sellingTab();
    const selected_line = tab.scrollable_area.content.selected_line;
    tab.scrollable_area.content.clearRetainingCapacity();
    var itr = self.inventory.items.iterator();
    while (itr.next()) |item_ptr| {
        var buffer: w.TextArea.Line = undefined;
        try tab.scrollable_area.content.addOption(
            self.alloc,
            try self.formatProduct(&buffer, item_ptr.*, false),
            item_ptr.*,
            sellOrDescribe,
            describeSelectedItem,
        );
    }
    if (tab.scrollable_area.content.options.items.len > 0) {
        try tab.scrollable_area.content.selectLine(if (selected_line < tab.scrollable_area.content.options.items.len)
            selected_line
        else
            tab.scrollable_area.content.options.items.len - 1);
    }
}

fn buyOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Buttons is helt. Show modal window for {any}", .{item});
    var area = w.OptionsArea(g.Entity).centered(self);
    try area.addOption(self.alloc, "Buy", item, buySelectedItem, null);
    try area.addOption(self.alloc, "Describe", item, describeSelectedItem, null);
    self.actions_window = .defaultModalWindow(area);
    // keep the main window opened
    return false;
}

fn sellOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var area = w.OptionsArea(g.Entity).centered(self);
    try area.addOption(self.alloc, "Sell", item, sellSelectedItem, null);
    try area.addOption(self.alloc, "Describe", item, describeSelectedItem, null);
    self.actions_window = .defaultModalWindow(area);
    // keep the main window opened
    return false;
}

fn buySelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const price = self.actualPrice(self.session.registry.getUnsafe(item, c.Price), true);
    log.debug("Buying item {d}", .{item.id});
    if (self.wallet.money >= price) {
        _ = self.shop.items.remove(item);
        try self.inventory.items.add(item);
        self.wallet.money -= price;
        try self.updateBuyingTab();
        try self.updateSellingTab();
    } else {
        self.modal_window = try w.notification(
            self.alloc,
            "You have not enough\nmoney.",
            .{ .max_region = MODAL_WINDOW_REGION },
        );
    }
    // close the modal window
    return true;
}

fn sellSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const price = self.actualPrice(self.session.registry.getUnsafe(item, c.Price), false);
    log.debug("Selling {d}", .{item.id});
    if (self.shop.balance >= price) {
        _ = self.inventory.items.remove(item);
        try self.shop.items.add(item);
        self.wallet.money += price;
        try self.updateBuyingTab();
        try self.updateSellingTab();
    } else {
        self.modal_window = try w.notification(
            self.alloc,
            "Traider doesn't have\nenough money",
            .{ .max_region = MODAL_WINDOW_REGION },
        );
    }
    // close the modal window
    return true;
}

fn describeSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Show info about item {d}", .{item.id});
    self.modal_window = try w.entityDescription(self.alloc, self.session, item);
    // keep the main window opened
    return false;
}
