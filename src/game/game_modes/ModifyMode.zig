//! In this mode the player can pay to somebody to recognize an unknown item,
//! or modify its equipment.
//! ```
//! ╔═══════════╗══════════════════════════╗
//! ║ Recognize ║   Modify      Repair     ║
//! ║           ╚══════════════════════════║
//! ║\ Pickaxe                         11$ ║
//! ║¿ A yellow potion                 22$ ║
//! ║                                      ║
//! ║                                      ║
//! ║                                      ║
//! ║                                      ║
//! ╚══════════════════════════════════════╝
//! ════════════════════════════════════════
//!  Your money:  900$    Close     Choose ⇧
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.modify_mode);

const MODAL_WINDOW_REGION: p.Region = p.Region.init(1, 2, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS - 2);

const IDENTIFY_COST = 0.45;
const REPAIR_BREAK_COST = 0.50;
const MOD_SOMEHOW_PRICE = 100;
const MOD_CAREFUL_PRICE = 200;
const MOD_MANUAL_PRICE = 300;

const CHANCE_TO_BREAK_ON_SOMEHOW = 30;
const CHANCE_TO_BREAK_ON_CAREFUL = 10;

const TAB_RECOGNIZE = 0;
const TAB_MODIFY = 1;
const TAB_REPAIR = 2;

const Self = @This();

session: *g.GameSession,
inventory: *c.Inventory,
wallet: *c.Wallet,
main_window: w.TabbedWindow,
modal_windows: w.ModalWindows = .empty,

pub fn init(
    self: *Self,
    session: *g.GameSession,
    inventory: *c.Inventory,
    wallet: *c.Wallet,
) !void {
    self.* = .{
        .session = session,
        .main_window = .{},
        .inventory = inventory,
        .wallet = wallet,
    };
    var tab = try self.main_window.addEmptyTab(self.allocator(), "Recognize");
    var area = try tab.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(tab.allocator(), self, .left);

    tab = try self.main_window.addEmptyTab(self.allocator(), "Modify");
    area = try tab.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(tab.allocator(), self, .left);

    tab = try self.main_window.addEmptyTab(self.allocator(), "Repair");
    area = try tab.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(tab.allocator(), self, .left);

    try self.updateTabs();
    try self.draw();
}

pub fn deinit(self: *Self) void {
    self.main_window.deinit(self.allocator());
    self.modal_windows.deinit(self.allocator());
}

pub fn allocator(self: *Self) std.mem.Allocator {
    return self.session.mode_arena.allocator();
}

pub fn tick(self: *Self) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.modal_windows.nonEmpty()) {
            try self.modal_windows.handleButton(btn);
        } else {
            if (try self.main_window.handleButton(btn) == .close_window) {
                // the  deinit method will be invoked here:
                try self.session.continuePlay(null, null);
                return;
            }
        }
        try self.draw();
    }
}

fn optionFromTab(self: Self, tab_idx: usize) *w.OptionsArea(g.Entity) {
    return @ptrCast(@alignCast(self.main_window.tabs[tab_idx].scrollable_area.content.underlying));
}

/// Recalculates the content of all tabs.
/// It should be done after every action.
pub fn updateTabs(self: *Self) !void {
    self.main_window.tabs[TAB_RECOGNIZE].scrollable_area.clearRetainingCapacity();
    self.main_window.tabs[TAB_MODIFY].scrollable_area.clearRetainingCapacity();
    self.main_window.tabs[TAB_REPAIR].scrollable_area.clearRetainingCapacity();

    const active_tab = self.main_window.activeTab();
    const active_content: *w.OptionsArea(g.Entity) = @ptrCast(@alignCast(active_tab.scrollable_area.content.underlying));

    var itr = self.inventory.items.iterator();
    while (itr.next()) |item_ptr| {
        const item = item_ptr.*;
        var buffer: [w.TabbedWindow.TAB_REGION.cols + 4]u8 = undefined;
        if (self.session.journal.isKnown(item)) {
            if (self.isWeaponOrArmor(item)) {
                if (g.meta.isBroken(&self.session.registry, item)) {
                    const price = self.calculateRepairingPrice(item);
                    try self.optionFromTab(TAB_REPAIR).addOption(
                        try self.formatLineWithPrice(&buffer, item, price),
                        item,
                        repairDescribe,
                        describeItem,
                    );
                } else {
                    try self.optionFromTab(TAB_MODIFY).addOption(
                        try self.formatLine(&buffer, item),
                        item,
                        modifyDescribe,
                        describeItem,
                    );
                }
            }
        } else {
            const price = self.calculateIdentificationPrice(item);
            try self.optionFromTab(TAB_RECOGNIZE).addOption(
                try self.formatLineWithPrice(&buffer, item, price),
                item,
                recognizeDescribe,
                describeItem,
            );
        }
    }
    if (active_tab.scrollable_area.content.totalLines() > 0) {
        const selected_line = active_content.selectedLine() orelse 0;
        try active_content.selectLine(
            if (selected_line < active_tab.scrollable_area.content.totalLines())
                selected_line
            else
                active_content.options.items.len - 1,
        );
    }
}

//[¿ A yellow potion                  22$ ]
const line_with_price_fmt = std.fmt.comptimePrint(
    "{{u}} {{s:<{d}}}{{d:4}}$ ",
    .{w.TabbedWindow.TAB_REGION.cols - 10}, // ("{u} ".len == 2) + ("0000$ ".len == 6) + 2 for borders
);

fn formatLineWithPrice(self: *Self, buffer: []u8, item: g.Entity, price: u16) ![]const u8 {
    const sprite = self.session.registry.getUnsafe(item, c.Sprite);
    var name_buf: [24]u8 = undefined;
    const name = try g.Description.printActualName(&name_buf, self.session.journal, item);
    return try std.fmt.bufPrint(buffer, line_with_price_fmt, .{ sprite.codepoint, name, price });
}

fn formatLine(self: *Self, buffer: []u8, item: g.Entity) ![]const u8 {
    const sprite = self.session.registry.getUnsafe(item, c.Sprite);
    return try std.fmt.bufPrint(
        buffer,
        "{u} {f}",
        .{ sprite.codepoint, g.Description.actualNameFormatter(self.session.journal, item) },
    );
}

inline fn isWeaponOrArmor(self: *Self, item: g.Entity) bool {
    return self.session.registry.has(item, c.Weapon) or self.session.registry.has(item, c.Armor);
}

fn recognizeDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.modal_windows.createOnTop(self.session.mode_arena.allocator(), MODAL_WINDOW_REGION);
    const area = try window.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(window.allocator(), self, .center);
    try area.addOption("Recognize", item, recognizeItem, null);
    try area.addOption("Describe", item, describeItem, null);
    window.shrinkToContent();
    // keep the main window opened
    return .keep_open;
}

fn recognizeItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const wallet = self.session.registry.getUnsafe(self.session.player, c.Wallet);
    const price = self.calculateIdentificationPrice(item);
    if (wallet.money >= price) {
        if (self.session.registry.has(item, c.Weapon))
            try self.session.journal.markWeaponAsKnown(item)
        else if (self.session.registry.has(item, c.Armor))
            try self.session.journal.markArmorAsKnown(item)
        else if (self.session.registry.get(item, c.Potion)) |potion|
            try self.session.journal.markPotionAsKnown(potion.*);

        wallet.money -= price;
        try self.updateTabs();
    } else {
        try self.modal_windows.windows.append(
            self.session.mode_arena.allocator(),
            try w.notification(
                self.session.mode_arena.allocator(),
                "You have not enough\nmoney.",
                .{ .max_region = MODAL_WINDOW_REGION },
            ),
        );
    }
    return .close_window;
}

fn repairDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.modal_windows.createOnTop(self.session.mode_arena.allocator(), MODAL_WINDOW_REGION);
    const area = try window.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(window.allocator(), self, .center);
    try area.addOption("Repair", item, repairItem, null);
    try area.addOption("Describe", item, describeItem, null);
    window.shrinkToContent();
    // keep the main window opened
    return .keep_open;
}

fn repairItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const wallet = self.session.registry.getUnsafe(self.session.player, c.Wallet);
    const price = self.calculateRepairingPrice(item);
    if (wallet.money >= price) {
        const breakages = self.session.registry.getUnsafe(item, c.Breakages);
        var itr = breakages.modifications.items.iterator();
        if (itr.next()) |modification| {
            breakages.modifications.remove(modification);
        }
        if (breakages.modifications.items.count() == 0)
            try self.session.registry.remove(item, c.Breakages);

        wallet.money -= price;
        try self.updateTabs();
    } else {
        try self.modal_windows.windows.append(
            self.session.mode_arena.allocator(),
            try w.notification(
                self.session.mode_arena.allocator(),
                "You have not enough\nmoney.",
                .{ .max_region = MODAL_WINDOW_REGION },
            ),
        );
    }
    return .close_window;
}

fn modifyDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.modal_windows.createOnTop(self.session.mode_arena.allocator(), MODAL_WINDOW_REGION);
    const area = try window.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(window.allocator(), self, .center);
    try area.addOption("Modify", item, modificationMode, null);
    try area.addOption("Describe", item, describeItem, null);
    window.shrinkToContent();
    // do not close the main window
    return .keep_open;
}

fn modificationMode(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.modal_windows.createOnTop(self.session.mode_arena.allocator(), MODAL_WINDOW_REGION);
    const area = try window.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(window.allocator(), self, .center);
    try area.addOptionFmt(
        "Somehow   {d}$",
        .{self.calculateModificationPrice(item, MOD_SOMEHOW_PRICE)},
        item,
        modifySomehow,
        null,
    );
    try area.addOptionFmt(
        "Carefully {d}$",
        .{self.calculateModificationPrice(item, MOD_CAREFUL_PRICE)},
        item,
        modifyCarefully,
        null,
    );
    try area.addOptionFmt(
        "Manually  {d}$",
        .{self.calculateModificationPrice(item, MOD_MANUAL_PRICE)},
        item,
        modifyManually,
        null,
    );
    try area.addOption("Help", item, showHelp, null);
    window.shrinkToContent();
    // close the previous modal window
    return .close_window;
}

fn modifySomehow(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.modify(item, CHANCE_TO_BREAK_ON_SOMEHOW, null, self.calculateModificationPrice(item, MOD_SOMEHOW_PRICE));
    return .close_window;
}

fn modifyCarefully(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.modify(item, CHANCE_TO_BREAK_ON_CAREFUL, null, self.calculateModificationPrice(item, MOD_CAREFUL_PRICE));
    return .close_window;
}

fn modifyManually(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.modal_windows.createOnTop(self.session.mode_arena.allocator(), MODAL_WINDOW_REGION);
    const area = try window.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(window.allocator(), self, .center);
    for (std.enums.values(c.Modification)) |modification| {
        try area.addOption(
            @tagName(modification),
            item,
            modifyManuallyEffect,
            null,
        );
    }
    window.shrinkToContent();
    // close the previous modal window
    return .close_window;
}

fn modifyManuallyEffect(ptr: *anyopaque, idx: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const modification: c.Modification = @enumFromInt(idx);
    try self.modify(item, 0, modification, self.calculateModificationPrice(item, MOD_MANUAL_PRICE));
    return .close_window;
}

fn modify(self: *Self, item: g.Entity, breakage_chance: u8, manual_modification: ?c.Modification, price: u16) !void {
    const wallet = self.session.registry.getUnsafe(self.session.player, c.Wallet);
    if (wallet.money < price) {
        try self.modal_windows.windows.append(
            self.session.mode_arena.allocator(),
            try w.notification(
                self.session.mode_arena.allocator(),
                "You have not enough\nmoney.",
                .{ .max_region = MODAL_WINDOW_REGION },
            ),
        );
        return;
    }
    var prng = std.Random.DefaultPrng.init(self.session.seed);
    const rand = prng.random();

    const should_become_broken = breakage_chance > 0 and rand.uintAtMost(u8, 100) < breakage_chance;
    const was_modified = if (should_become_broken)
        try g.meta.breakItem(&self.session.registry, rand, item, manual_modification)
    else
        try g.meta.improveItem(&self.session.registry, rand, item, manual_modification);

    if (!was_modified) {
        if (!should_become_broken)
            try self.modal_windows.windows.append(
                self.session.mode_arena.allocator(),
                try w.notification(
                    self.session.mode_arena.allocator(),
                    "All possible modifications\nalready applied",
                    .{ .max_region = MODAL_WINDOW_REGION },
                ),
            );
        return;
    }

    if (self.session.registry.has(item, c.Weapon)) {
        try self.session.journal.forgetWeapon(item);
    } else if (self.session.registry.has(item, c.Armor)) {
        try self.session.journal.forgetArmor(item);
    }
    wallet.money -= price;
    try self.updateTabs();
}

fn showHelp(ptr: *anyopaque, _: usize, _: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.modal_windows.windows.append(
        self.session.mode_arena.allocator(),
        try w.notification(
            self.session.mode_arena.allocator(),
            \\An arbitrary  modification  has a 
            \\30% chance of breaking the item.
            \\
            \\A  careful  modification  reduces 
            \\this risk to 10%.
            \\
            \\A manual modification allows  you  
            \\to  choose  the  specific  effect 
            \\to add to the item.
        ,
            .{ .title = "Help", .text_align = .left },
        ),
    );
    // Do not close the previous window
    return .keep_open;
}

fn describeItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.modal_windows.windows.append(
        self.session.mode_arena.allocator(),
        try w.entityDescription(self.session.mode_arena.allocator(), self.session, item),
    );
    // Do not close the previous window
    return .keep_open;
}

fn draw(self: *Self) !void {
    try self.main_window.draw(self.session.render);
    var buf: [20]u8 = undefined;
    const money = self.session.registry.getUnsafe(self.session.player, c.Wallet).money;
    try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "Your money: {d:4}$", .{money}));
    if (self.modal_windows.nonEmpty()) {
        try self.modal_windows.draw(self.session.render);
    }
}

fn calculateIdentificationPrice(self: Self, item: g.Entity) u16 {
    const item_price: f32 = @floatFromInt(self.session.registry.getUnsafe(item, c.Price).value);
    return @intFromFloat(item_price * IDENTIFY_COST);
}

fn calculateRepairingPrice(self: Self, item: g.Entity) u16 {
    const item_price: f32 = @floatFromInt(self.session.registry.getUnsafe(item, c.Price).value);
    return @intFromFloat(item_price * REPAIR_BREAK_COST);
}

fn calculateModificationPrice(self: Self, item: g.Entity, base_price: u16) u16 {
    const modifications_count: u16 = if (self.session.registry.get(item, c.Improvements)) |improvements|
        @truncate(improvements.modifications.items.count())
    else
        0;

    return base_price * (modifications_count + 1);
}
