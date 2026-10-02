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

/// The biggest region that can be occupied by a modal window with options
const MODAL_WINDOW_REGION: p.Region = p.Region.init(3, 2, g.DISPLAY_ROWS - 5, g.DISPLAY_COLS - 2);

const Self = @This();

const MainWindow = w.TabbedWindow(.{ w.OptionsArea(g.Entity), w.OptionsArea(g.Entity), w.OptionsArea(g.Entity) });

session: *g.GameSession,
inventory: *c.Inventory,
wallet: *c.Wallet,
main_window: MainWindow,
compositor: w.WindowCompositor(MainWindow),

pub fn init(
    self: *Self,
    session: *g.GameSession,
    inventory: *c.Inventory,
    wallet: *c.Wallet,
) !void {
    self.* = .{
        .session = session,
        .main_window = .empty,
        .compositor = .init(session.mode_arena.allocator(), &self.main_window, MODAL_WINDOW_REGION),
        .inventory = inventory,
        .wallet = wallet,
    };
    _ = try self.main_window.addTab(
        "Recognize",
        w.OptionsArea(g.Entity).initEmpty(self.allocator(), self, .left),
    );

    _ = try self.main_window.addTab(
        "Modify",
        w.OptionsArea(g.Entity).initEmpty(self.allocator(), self, .left),
    );

    _ = try self.main_window.addTab(
        "Repair",
        w.OptionsArea(g.Entity).initEmpty(self.allocator(), self, .left),
    );

    try self.updateTabs();
    try self.draw();
}

pub fn deinit(self: *Self) void {
    self.compositor.deinit();
}

fn allocator(self: *Self) std.mem.Allocator {
    return self.session.mode_arena.allocator();
}

pub fn tick(self: *Self) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (try self.compositor.handleButton(btn) == .close_window) {
            // the  deinit method will be invoked here:
            try self.session.continuePlay(null, null);
            return;
        }
        try self.draw();
    }
}

fn optionFromTab(self: *Self, tab_idx: usize) *w.OptionsArea(g.Entity) {
    return self.main_window.getArea(w.OptionsArea(g.Entity), tab_idx).?;
}

/// Recalculates the content of all tabs.
/// It should be done after every action.
pub fn updateTabs(self: *Self) !void {
    self.optionFromTab(TAB_RECOGNIZE).clearRetainingCapacity();
    self.optionFromTab(TAB_MODIFY).clearRetainingCapacity();
    self.optionFromTab(TAB_REPAIR).clearRetainingCapacity();

    const active_content = self.optionFromTab(self.main_window.active_tab_idx);

    var itr = self.inventory.items.iterator();
    while (itr.next()) |item_ptr| {
        const item = item_ptr.*;
        var buffer: [g.DISPLAY_COLS + 4]u8 = undefined;
        if (self.session.journal.isKnown(item)) {
            if (self.isWeaponOrArmor(item)) {
                if (g.meta.isBroken(&self.session.registry, item)) {
                    const price = self.calculateRepairingPrice(item);
                    _ = try self.optionFromTab(TAB_REPAIR).addOption(
                        try self.formatLineWithPrice(&buffer, item, price),
                        item,
                        .{ .handle_release_button = repairDescribe, .handle_hold_button = describeItem },
                    );
                } else {
                    _ = try self.optionFromTab(TAB_MODIFY).addOption(
                        try self.formatLine(&buffer, item),
                        item,
                        .{ .handle_release_button = modifyDescribe, .handle_hold_button = describeItem },
                    );
                }
            }
        } else {
            const price = self.calculateIdentificationPrice(item);
            _ = try self.optionFromTab(TAB_RECOGNIZE).addOption(
                try self.formatLineWithPrice(&buffer, item, price),
                item,
                .{ .handle_release_button = recognizeDescribe, .handle_hold_button = describeItem },
            );
        }
    }
    if (active_content.totalLines() > 0) {
        const selected_line = active_content.selectedLine() orelse 0;
        try active_content.selectLine(
            if (selected_line < active_content.totalLines())
                selected_line
            else
                active_content.options.items.len - 1,
        );
    }
}

//[¿ A yellow potion                  22$ ]
const line_with_price_fmt = std.fmt.comptimePrint(
    "{{u}} {{s:<{d}}}{{d:4}}$ ",
    .{g.DISPLAY_COLS - 10}, // ("{u} ".len == 2) + ("0000$ ".len == 6) + 2 for borders
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
    const window = try self.compositor.showModalWindowWithOptions(self.allocator(), &.{}, g.Entity, self, .center);
    const area = &window.panel.area;
    _ = try area.addOption("Recognize", item, .{ .handle_release_button = recognizeItem });
    _ = try area.addOption("Describe", item, .{ .handle_release_button = describeItem });
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
        try self.compositor.showNotification(
            self.allocator(),
            &.{},
            "You have not enough\nmoney.",
        );
    }
    return .close_window;
}

fn repairDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.compositor.showModalWindowWithOptions(self.allocator(), &.{}, g.Entity, self, .center);
    const area = &window.panel.area;
    _ = try area.addOption("Repair", item, .{ .handle_release_button = repairItem });
    _ = try area.addOption("Describe", item, .{ .handle_release_button = describeItem });
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
        try self.compositor.showNotification(
            self.allocator(),
            &.{},
            "You have not enough\nmoney.",
        );
    }
    return .close_window;
}

fn modifyDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.compositor.showModalWindowWithOptions(self.allocator(), &.{}, g.Entity, self, .center);
    const area = &window.panel.area;
    _ = try area.addOption("Modify", item, .{ .handle_release_button = modificationMode });
    _ = try area.addOption("Describe", item, .{ .handle_release_button = describeItem });
    window.shrinkToContent();
    // do not close the main window
    return .keep_open;
}

fn modificationMode(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.compositor.showModalWindowWithOptions(self.allocator(), &.{}, g.Entity, self, .center);
    const area = &window.panel.area;
    _ = try area.addOptionFmt(
        "Somehow   {d}$",
        .{self.calculateModificationPrice(item, MOD_SOMEHOW_PRICE)},
        item,
        .{ .handle_release_button = modifySomehow },
    );
    _ = try area.addOptionFmt(
        "Carefully {d}$",
        .{self.calculateModificationPrice(item, MOD_CAREFUL_PRICE)},
        item,
        .{ .handle_release_button = modifyCarefully },
    );
    _ = try area.addOptionFmt(
        "Manually  {d}$",
        .{self.calculateModificationPrice(item, MOD_MANUAL_PRICE)},
        item,
        .{ .handle_release_button = modifyManually },
    );
    _ = try area.addOption("Help", item, .{ .handle_release_button = showHelp });
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
    const window = try self.compositor.showModalWindowWithOptions(self.allocator(), &.{}, g.Entity, self, .center);
    const area = &window.panel.area;
    for (std.enums.values(c.Modification)) |modification| {
        _ = try area.addOption(
            @tagName(modification),
            item,
            .{ .handle_release_button = modifyManuallyEffect },
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
        try self.compositor.showNotification(
            self.allocator(),
            &.{},
            "You have not enough\nmoney.",
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
            try self.compositor.showNotification(
                self.allocator(),
                &.{},
                "All possible modifications\nalready applied",
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
    try self.compositor.showNotification(self.allocator(), "Help",
        \\An arbitrary  modification  has a 
        \\30% chance of breaking the item.
        \\
        \\A  careful  modification  reduces 
        \\this risk to 10%.
        \\
        \\A manual modification allows  you  
        \\to  choose  the  specific  effect 
        \\to add to the item.
    );
    // Do not close the previous window
    return .keep_open;
}

fn describeItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.compositor.showEntityDescription(self.allocator(), self.session, item);
    // Do not close the previous window
    return .keep_open;
}

fn draw(self: *Self) !void {
    var buf: [20]u8 = undefined;
    const money = self.session.registry.getUnsafe(self.session.player, c.Wallet).money;
    try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "Your money: {d:4}$", .{money}));
    try self.compositor.draw(self.session.render);
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
