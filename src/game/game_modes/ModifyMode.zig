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
//! 1════════════════════════════════════════╗ 2════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║ ║ ╔═════════════════╔═══════════════════╗║
//! ║ ║   Recognize     ║       Modify      ║║ ║ ║   Recognize     ║       Modify      ║║
//! ║╔╝═════════════════╝                   ║║ ║╔╝═════════════════╝                   ║║
//! ║║░\░Club░░░░░░░░░░░░░░░░░░░░░░░░░░100$░║║ ║║ ┌───────────────────────────────────┐║║
//! ║║ { Bow                           100$ ║║ ║║ │                                   │║║
//! ║║                                      ║║ ║║ │             Describe              │║║
//! ║║                                      ║║ ║║ │              Modify               │║║
//! ║║                                      ║║ ║║ │               Help                │║║
//! ║║                                      ║║ ║║ │                                   │║║
//! ║║                                      ║║ ║║ └───────────────────────────────────┘║║
//! ║╚══════════════════════════════════════╝║ ║╚══════════════════════════════════════╝║
//! ║════════════════════════════════════════║ ║════════════════════════════════════════║
//! ║    000$             Close       Choose ║ ║    000$             Close       Choose ║
//! ╚════════════════════════════════════════╝ ╚════════════════════════════════════════╝
//! 3════════════════════════════════════════╗ 4════════════════════════════════════════╗
//! ║ ╔═════════════════╔═══════════════════╗║ ║ ╔═════════════════╗═══════════════════╗║
//! ║ ║   Recognize     ║       Modify      ║║ ║ ║   Recognize     ║       Modify      ║║
//! ║╔╝═════════════════╝                   ║║ ║╔╝═════════════════╝                   ║║
//! ║║ ┌───────────────────────────────────┐║║ ║║ ┌───────────────────────────────────┐║║
//! ║║ │                                   │║║ ║║ │            Physic                 │║║
//! ║║ │           Somehow    x1           │║║ ║║ │             Fire                  │║║
//! ║║ │           Carefully  x2           │║║ ║║ │             Acid                  │║║
//! ║║ │           Manually   x3           │║║ ║║ │            Poison                 │║║
//! ║║ │                                   │║║ ║║ └───────────────────────────────────┘║║
//! ║║ └───────────────────────────────────┘║║ ║║                                      ║║
//! ║╚══════════════════════════════════════╝║ ║╚══════════════════════════════════════╝║
//! ║════════════════════════════════════════║ ║════════════════════════════════════════║
//! ║    000$             Close       Choose ║ ║    000$             Close       Choose ║
//! ╚════════════════════════════════════════╝ ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.modify_mode);

const MODAL_WINDOW_REGION: p.Region = p.Region.init(3, 2, g.DISPLAY_ROWS - 5, g.DISPLAY_COLS - 2);

const IDENTIFY_COST = 0.45;
const REPAIR_BREAK_COST = 0.50;
const MOD_SOMEHOW_COST = 0.35;
const MOD_CAREFUL_COST = 1.05;
const MOD_MANUAL_COST = 2.80;

const CHANCE_TO_BREAK_ON_SOMEHOW = 30;
const CHANCE_TO_BREAK_ON_CAREFUL = 10;

const Self = @This();

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
    session: *g.GameSession,
    inventory: *c.Inventory,
    wallet: *c.Wallet,
) !void {
    self.* = .{
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
        window.deinit(self.session.mode_arena.allocator());
    }
    if (self.actions_window) |*window| {
        window.deinit(self.session.mode_arena.allocator());
    }
    self.main_window.deinit(self.session.mode_arena.allocator());
}

pub fn tick(self: *Self) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.modal_window) |*window| {
            if (try window.handleButton(btn)) {
                log.debug("Close modal window", .{});
                try self.main_window.draw(self.session.render);
                window.deinit(self.session.mode_arena.allocator());
                self.modal_window = null;
            }
        } else if (self.actions_window) |*window| {
            if (try window.handleButton(btn)) {
                log.debug("Close actions window", .{});
                try self.main_window.draw(self.session.render);
                window.deinit(self.session.mode_arena.allocator());
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

/// Recalculates the content of the both tabs.
/// It should be done after every modification/recognition.
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
            if (self.isWeaponOrArmor(item)) {
                try self.tabModify().scrollable_area.content.addOption(
                    self.session.mode_arena.allocator(),
                    try self.formatLine(&buffer, item),
                    item,
                    modifyDescribe,
                    describeItem,
                );
            }
        } else {
            const price = self.calculateIdentificationPrice(item);
            try self.tabRecognize().scrollable_area.content.addOption(
                self.session.mode_arena.allocator(),
                try self.formatLineWithPrice(&buffer, item, price),
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

const line_with_price_fmt = std.fmt.comptimePrint(
    "{{u}} {{s:<{d}}}{{d:4}}$",
    .{w.WindowWithTabs.CONTENT_AREA_REGION.cols - 8}, // "{u} ".len == 2 + "0000$".len == 5 + 1 for the right pad
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

fn recognizeDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var area = w.OptionsArea(g.Entity).centered(self);
    try area.addOption(self.session.mode_arena.allocator(), "Recognize", item, recognizeItem, null);
    try area.addOption(self.session.mode_arena.allocator(), "Describe", item, describeItem, null);
    self.actions_window = .modalWindow(area, MODAL_WINDOW_REGION);
    // keep the main window opened
    return false;
}

fn recognizeItem(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
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
        self.modal_window = try w.notification(
            self.session.mode_arena.allocator(),
            "You have not enough\nmoney.",
            .{ .max_region = MODAL_WINDOW_REGION },
        );
    }
    return true;
}

fn modifyDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var area = w.OptionsArea(g.Entity).centered(self);
    try area.addOption(self.session.mode_arena.allocator(), "Modify", item, modificationMode, null);
    try area.addOption(self.session.mode_arena.allocator(), "Describe", item, describeItem, null);
    try area.addOption(self.session.mode_arena.allocator(), "Help", item, showHelp, null);
    self.actions_window = .modalWindow(area, MODAL_WINDOW_REGION);
    // keep the main window opened
    return false;
}

fn showHelp(ptr: *anyopaque, _: usize, _: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.modal_window = try w.notification(
        self.session.mode_arena.allocator(),
        \\The  damage of  the chosen weapon
        \\or  the  protection  provided  by  
        \\armor will be altered. The  final 
        \\outcome     depends    on     how
        \\carefully  the   modification  is 
        \\performed.
        \\
        \\An arbitrary  modification  has a 
        \\30%    chance  of  worsening  the 
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

fn modificationMode(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.actions_window.?.deinit(self.session.mode_arena.allocator());
    var area = w.OptionsArea(g.Entity).centered(self);
    try area.addOptionFmt(
        self.session.mode_arena.allocator(),
        "Somehow   {d}$",
        .{self.calculateSomehowModificationPrice(item)},
        item,
        modifySomehow,
        null,
    );
    try area.addOptionFmt(
        self.session.mode_arena.allocator(),
        "Carefully {d}$",
        .{self.calculateCarefulModificationPrice(item)},
        item,
        modifyCarefully,
        null,
    );
    try area.addOptionFmt(
        self.session.mode_arena.allocator(),
        "Manually  {d}$",
        .{self.calculateManualModificationPrice(item)},
        item,
        modifyManually,
        null,
    );
    self.actions_window = .modalWindow(area, MODAL_WINDOW_REGION);
    // keep the main window opened
    return false;
}

fn modifySomehow(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.modify(item, CHANCE_TO_BREAK_ON_SOMEHOW, null, self.calculateSomehowModificationPrice(item));
    return true;
}

fn modifyCarefully(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.modify(item, CHANCE_TO_BREAK_ON_CAREFUL, null, self.calculateCarefulModificationPrice(item));
    return true;
}

fn modifyManually(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const options = &self.actions_window.?.scrollable_area.content;
    log.debug("Show the list of possible effects", .{});
    options.clearRetainingCapacity();
    for (std.enums.values(c.Modification)) |modification| {
        try options.addOption(
            self.session.mode_arena.allocator(),
            @tagName(modification),
            item,
            modifyManuallyEffect,
            null,
        );
    }
    // Do not close the action_window, because we recreate it here
    return false;
}

fn modifyManuallyEffect(ptr: *anyopaque, idx: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const modification: c.Modification = @enumFromInt(idx);
    try self.modify(item, 0, modification, self.calculateManualModificationPrice(item));
    return true;
}

fn modify(self: *Self, item: g.Entity, breakage_chance: u8, manual_modification: ?c.Modification, price: u16) !void {
    const wallet = self.session.registry.getUnsafe(self.session.player, c.Wallet);
    if (wallet.money < price) {
        self.modal_window = try w.notification(
            self.session.mode_arena.allocator(),
            "You have not enough\nmoney.",
            .{ .max_region = MODAL_WINDOW_REGION },
        );
        return;
    }
    var prng = std.Random.DefaultPrng.init(self.session.seed);
    const rand = prng.random();

    const should_become_broken = breakage_chance > 0 and rand.uintAtMost(u8, 100) < breakage_chance;
    const modifications = if (should_become_broken)
        &(try self.session.registry.getOrSet(item, c.Breakages, .empty)).modifications
    else
        &(try self.session.registry.getOrSet(item, c.Improvements, .empty)).modifications;
    const modification = if (manual_modification) |mm|
        mm
    else
        self.chooseModification(rand, item, should_become_broken, modifications);

    modifications.add(modification);

    if (self.session.registry.has(item, c.Weapon)) {
        try self.session.journal.forgetWeapon(item);
    } else if (self.session.registry.has(item, c.Armor)) {
        try self.session.journal.forgetArmor(item);
    }
    wallet.money -= price;
    try self.updateTabs();
}

fn chooseModification(
    self: Self,
    rand: std.Random,
    item: g.Entity,
    should_become_broken: bool,
    modifications: *const c.Modifications,
) c.Modification {
    var proportions = if (should_become_broken) c.Breakages.proportions else c.Improvements.proportions;
    var itr = modifications.iterator();
    while (itr.next()) |m| {
        proportions[@intFromEnum(m)] = 0;
    }
    if (should_become_broken and self.session.registry.has(item, c.Weapon)) {
        for (std.enums.values(c.ElementalEffect)) |e| {
            proportions[@intFromEnum(e)] = 0;
        }
    }
    return @enumFromInt(rand.weightedIndex(u8, &proportions));
}

fn describeItem(ptr: *anyopaque, _: usize, item: g.Entity) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Show info about item {d}", .{item.id});
    self.modal_window = try w.entityDescription(self.session.mode_arena.allocator(), self.session, item);
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

fn calculateIdentificationPrice(self: Self, item: g.Entity) u16 {
    const item_price: f32 = @floatFromInt(self.session.registry.getUnsafe(item, c.Price).value);
    return @intFromFloat(item_price * IDENTIFY_COST);
}

fn calculateRepairPrice(self: Self, item: g.Entity) u16 {
    const item_price: f32 = @floatFromInt(self.session.registry.getUnsafe(item, c.Price).value);
    return @intFromFloat(item_price * REPAIR_BREAK_COST);
}

fn calculateSomehowModificationPrice(self: Self, item: g.Entity) u16 {
    const item_price: f32 = @floatFromInt(self.session.registry.getUnsafe(item, c.Price).value);
    return @intFromFloat(item_price * MOD_SOMEHOW_COST);
}

fn calculateCarefulModificationPrice(self: Self, item: g.Entity) u16 {
    const item_price: f32 = @floatFromInt(self.session.registry.getUnsafe(item, c.Price).value);
    return @intFromFloat(item_price * MOD_CAREFUL_COST);
}

fn calculateManualModificationPrice(self: Self, item: g.Entity) u16 {
    const item_price: f32 = @floatFromInt(self.session.registry.getUnsafe(item, c.Price).value);
    return @intFromFloat(item_price * MOD_MANUAL_COST);
}
