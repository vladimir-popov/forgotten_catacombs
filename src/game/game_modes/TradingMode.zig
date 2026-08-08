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

session: *g.GameSession,
player_wallet: *c.Wallet,
inventory: *c.Inventory,
shop: *c.Shop,
shop_wallet: *c.Wallet,
main_window: w.WindowWithTabs = .{},
/// Contains an entity description, or a notification.
modal_window: ?w.ModalWindow(w.TextArea) = null,
/// Contains available actions
actions_window: ?w.ModalWindow(w.OptionsArea(g.Entity)) = null,

pub fn init(
    self: *Self,
    session: *g.GameSession,
    shop: g.Entity,
) !void {
    self.* = .{
        .session = session,
        .player_wallet = session.registry.getUnsafe(session.player, c.Wallet),
        .inventory = session.registry.getUnsafe(session.player, c.Inventory),
        .shop = session.registry.getUnsafe(shop, c.Shop),
        .shop_wallet = session.registry.getUnsafe(shop, c.Wallet),
    };
    var prng = std.Random.DefaultPrng.init(session.level.dungeon.seed);
    try g.entities.generators.fillShop(
        &session.registry,
        prng.random(),
        self.shop,
        session.max_depth,
    );
    self.main_window.addTab("Buy", self);
    try self.updateBuyingTab();

    self.main_window.addTab("Sell", self);
    try self.updateSellingTab();

    try self.draw();
}

pub fn deinit(self: *Self) void {
    if (self.modal_window) |*window| {
        window.deinit(self.session.mode_arena.allocator());
    }
    if (self.actions_window) |*window| {
        window.deinit(self.session.mode_arena.allocator());
    }
    self.main_window.deinit(self.session.mode_arena.allocator());
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
            if (try window.handleButton(btn) == .close_window) {
                std.log.debug("Close description window", .{});
                try self.main_window.draw(self.session.render);
                window.deinit(self.session.mode_arena.allocator());
                self.modal_window = null;
            }
        } else if (self.actions_window) |*window| {
            if (try window.handleButton(btn) == .close_window) {
                std.log.debug("Close actions window", .{});
                try self.main_window.draw(self.session.render);
                window.deinit(self.session.mode_arena.allocator());
                self.actions_window = null;
            }
        } else {
            if (try self.main_window.handleButton(btn) == .close_window) {
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
                    self.shop_wallet.money = money;
                } else {
                    self.player_wallet.money = money;
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
        try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "Traider's:  {d:4}$", .{self.shop_wallet.money}));
    } else {
        try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "Your money: {d:4}$", .{self.player_wallet.money}));
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
        const name = try g.Description.printActualName(&buf, self.session.journal, item);
        const price_value = if (for_buying) price.value else g.meta.sellingPrice(self.session.journal, item, price);
        return try std.fmt.bufPrint(
            line,
            product_fmt,
            .{ sprite.codepoint, name, price_value },
        );
    } else {
        std.debug.panic("Error on format product. Some component was not found", .{});
    }
}

fn formatItemForBuying(ptr: *anyopaque, line: *w.TextArea.Line, item: g.Entity) ![]const u8 {
    return try formatProduct(@ptrCast(@alignCast(ptr)), line, item, true);
}

fn formatItemForSelling(ptr: *anyopaque, line: *w.TextArea.Line, item: g.Entity) ![]const u8 {
    return try formatProduct(@ptrCast(@alignCast(ptr)), line, item, false);
}

fn updateBuyingTab(self: *Self) !void {
    const tab = self.buyingTab();
    try w.updateAreaWithItems(
        &self.session.mode_arena,
        self,
        self.shop.items,
        formatItemForBuying,
        buyOrDescribe,
        describeSelectedItem,
        &tab.scrollable_area,
    );
}

fn updateSellingTab(self: *Self) !void {
    const tab = self.sellingTab();
    try w.updateAreaWithItems(
        &self.session.mode_arena,
        self,
        self.inventory.items,
        formatItemForSelling,
        sellOrDescribe,
        describeSelectedItem,
        &tab.scrollable_area,
    );
}

fn buyOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Buttons is helt. Show modal window for {any}", .{item});
    var area = w.OptionsArea(g.Entity).centered(self);
    try area.addOption(self.session.mode_arena.allocator(), "Buy", item, buySelectedItem, null);
    try area.addOption(self.session.mode_arena.allocator(), "Describe", item, describeSelectedItem, null);
    self.actions_window = .defaultModalWindow(area);
    // keep the main window opened
    return .keep_open;
}

fn sellOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var area = w.OptionsArea(g.Entity).centered(self);
    try area.addOption(self.session.mode_arena.allocator(), "Sell", item, sellSelectedItem, null);
    try area.addOption(self.session.mode_arena.allocator(), "Describe", item, describeSelectedItem, null);
    self.actions_window = .defaultModalWindow(area);
    // keep the main window opened
    return .keep_open;
}

fn buySelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const price = self.session.registry.getUnsafe(item, c.Price).value;
    log.debug("Buying item {d}", .{item.id});
    if (self.player_wallet.money >= price) {
        _ = self.shop.items.remove(item);
        try self.inventory.items.add(item);
        // TODO: create a test to control transaction
        self.player_wallet.money -= price;
        self.shop_wallet.money += price;
        try self.updateBuyingTab();
        try self.updateSellingTab();
    } else {
        self.modal_window = try w.notification(
            self.session.mode_arena.allocator(),
            "You have not enough\nmoney.",
            .{ .max_region = MODAL_WINDOW_REGION },
        );
    }
    // close the modal window
    return .close_window;
}

fn sellSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const price = g.meta.sellingPrice(self.session.journal, item, self.session.registry.getUnsafe(item, c.Price));
    log.debug("Selling {d}", .{item.id});
    if (self.shop_wallet.money >= price) {
        _ = self.inventory.items.remove(item);
        try self.shop.items.add(item);
        // TODO: create a test to control transaction
        self.player_wallet.money += price;
        self.shop_wallet.money -= price;
        try self.updateBuyingTab();
        try self.updateSellingTab();
    } else {
        self.modal_window = try w.notification(
            self.session.mode_arena.allocator(),
            "Traider doesn't have\nenough money",
            .{ .max_region = MODAL_WINDOW_REGION },
        );
    }
    // close the modal window
    return .close_window;
}

fn describeSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Show info about item {d}", .{item.id});
    self.modal_window = try w.entityDescription(self.session.mode_arena.allocator(), self.session, item);
    // keep the main window opened
    return .keep_open;
}
