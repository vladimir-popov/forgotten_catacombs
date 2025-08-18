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

const Self = @This();

alloc: std.mem.Allocator,
session: *g.GameSession,
wallet: *c.Wallet,
inventory: *c.Inventory,
shop: *c.Shop,
main_window: w.WindowWithTabs,
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
        .wallet = session.entities.registry.getUnsafe(session.player, c.Wallet),
        .inventory = session.entities.registry.getUnsafe(session.player, c.Inventory),
        .shop = shop,
        .main_window = w.WindowWithTabs.init(self),
    };
    self.main_window.addTab("Buy");
    try self.updateBuyingTab();

    self.main_window.addTab("Sell");
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

fn buyingTab(self: *Self) *w.WindowWithTabs.Tab {
    return &self.main_window.tabs[0];
}

fn sellingTab(self: *Self) *w.WindowWithTabs.Tab {
    return &self.main_window.tabs[1];
}

pub fn tick(self: *Self) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.modal_window) |*window| {
            if (try window.handleButton(btn)) {
                std.log.debug("Close description window", .{});
                try window.hide(self.session.render, .fill_region);
                window.deinit(self.alloc);
                self.modal_window = null;
            }
        } else if (self.actions_window) |*window| {
            if (try window.handleButton(btn)) {
                std.log.debug("Close actions window", .{});
                try window.hide(self.session.render, .fill_region);
                window.deinit(self.alloc);
                self.actions_window = null;
            }
        } else {
            if (try self.main_window.handleButton(btn)) {
                try self.session.play(null);
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
    if (self.main_window.active_tab_idx == 0) {
        try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "Traider's: {d:4}$", .{self.shop.balance}));
    } else {
        try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "Your:      {d:4}$", .{self.wallet.money}));
    }
}

const product_fmt = std.fmt.comptimePrint(
    "{{u}} {{s:<{d}}}{{d:4}}$",
    .{w.WindowWithTabs.CONTENT_AREA_REGION.cols - 9}, // "{u} ".len == 2 + "0000$".len == 5 + 2 for pads
);

fn formatProduct(self: *Self, line: *w.TextArea.Line, item: g.Entity, for_buying: bool) ![]const u8 {
    if (self.session.entities.registry.get3(item, c.Price, c.Description, c.Sprite)) |tuple| {
        const price, const description, const sprite = tuple;
        return try std.fmt.bufPrint(
            line,
            product_fmt,
            .{ sprite.codepoint, description.name(), self.actualPrice(price, for_buying) },
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
    tab.area.clearRetainingCapacity();
    var itr = self.shop.items.iterator();
    while (itr.next()) |item_ptr| {
        var buffer: w.TextArea.Line = undefined;
        try tab.area.addOption(
            self.alloc,
            try self.formatProduct(&buffer, item_ptr.*, true),
            item_ptr.*,
            buyOrDescribe,
            describeSelectedItem,
        );
    }
    if (tab.area.options.items.len > 0) {
        try tab.area.selectLine(if (tab.area.selected_line < tab.area.options.items.len)
            tab.area.selected_line
        else
            tab.area.options.items.len - 1);
    }
}

fn updateSellingTab(self: *Self) !void {
    const tab = self.sellingTab();
    tab.area.clearRetainingCapacity();
    var itr = self.inventory.items.iterator();
    while (itr.next()) |item_ptr| {
        var buffer: w.TextArea.Line = undefined;
        try tab.area.addOption(
            self.alloc,
            try self.formatProduct(&buffer, item_ptr.*, false),
            item_ptr.*,
            sellOrDescribe,
            describeSelectedItem,
        );
    }
    if (tab.area.options.items.len > 0) {
        try tab.area.selectLine(if (tab.area.selected_line < tab.area.options.items.len)
            tab.area.selected_line
        else
            tab.area.options.items.len - 1);
    }
}

fn buyOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Buttons is helt. Show modal window for {any}", .{item});
    var window = w.options(g.Entity, self);
    try window.area.addOption(self.alloc, "Buy", item, buySelectedItem, null);
    try window.area.addOption(self.alloc, "Describe", item, describeSelectedItem, null);
    self.actions_window = window;
}

fn sellOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var window = w.options(g.Entity, self);
    try window.area.addOption(self.alloc, "Sell", item, sellSelectedItem, null);
    try window.area.addOption(self.alloc, "Describe", item, describeSelectedItem, null);
    self.actions_window = window;
}

fn buySelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const price = self.actualPrice(self.session.entities.registry.getUnsafe(item, c.Price), true);
    log.debug("Buying item {d}", .{item.id});
    if (self.wallet.money > price) {
        _ = self.shop.items.remove(item);
        try self.inventory.items.add(item);
        self.wallet.money -= price;
        try self.updateBuyingTab();
        try self.updateSellingTab();
    } else {
        self.modal_window = try w.notification(self.alloc, "You have not enough money");
    }
}

fn sellSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const price = self.actualPrice(self.session.entities.registry.getUnsafe(item, c.Price), false);
    log.debug("Selling {d}", .{item.id});
    if (self.shop.balance > price) {
        _ = self.inventory.items.remove(item);
        try self.shop.items.add(item);
        self.wallet.money += price;
        try self.updateBuyingTab();
        try self.updateSellingTab();
    } else {
        self.modal_window = try w.notification(self.alloc, "Traider doesn't have enough money");
    }
}

fn describeSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Show info about item {d}", .{item.id});
    self.modal_window = try w.entityDescription(
        self.alloc,
        self.session.entities,
        item,
        self.session.runtime.isDevMode(),
    );
}
