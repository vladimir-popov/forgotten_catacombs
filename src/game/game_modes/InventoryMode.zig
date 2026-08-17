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

const ResolvedCombination = g.systems.CombinationSystem.ResolvedCombination;

const log = std.log.scoped(.inventory_mode);

const MODAL_WINDOW_REGION: p.Region = p.Region.init(2, 2, g.DISPLAY_ROWS - 4, g.DISPLAY_COLS - 2);

const Self = @This();

session: *g.GameSession,
main_window: w.TabbedWindow,
inventory: *c.Inventory,
equipment: *c.Equipment,
/// The entity under the player's feet. Can be a pile or a single item
drop: ?g.Entity,
/// The action initiated during manage the inventory.
action: ?g.actions.Action = null,
/// The stack of modal windows
modal_windows: w.ModalWindows = .empty,

pub fn init(
    self: *Self,
    session: *g.GameSession,
    equipment: *c.Equipment,
    inventory: *c.Inventory,
    drop: ?g.Entity,
) !void {
    log.debug("Init inventory with drop {any}", .{drop});
    self.* = .{
        .session = session,
        .main_window = .{},
        .equipment = equipment,
        .inventory = inventory,
        .drop = drop,
    };
    try self.addInventoryTab();

    if (drop) |item| {
        try self.addDropTab(item);
    }
    try self.draw();
}

pub fn tick(self: *Self) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.modal_windows.nonEmpty()) {
            try self.modal_windows.handleButton(btn);
        } else {
            if (try self.main_window.handleButton(btn) == .close_window) {
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
    try self.main_window.draw(self.session.render);
    var buf: [10]u8 = undefined;
    const money = self.session.registry.getUnsafe(self.session.player, c.Wallet).money;
    try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "{d}$", .{money}));
    if (self.modal_windows.nonEmpty()) {
        try self.modal_windows.draw(self.session.render);
    }
}

fn tabWithInventory(self: *Self) *w.Window {
    return &self.main_window.tabs[0];
}

fn tabWithDrop(self: *Self) ?*w.Window {
    return if (self.main_window.tabs_count > 1)
        &self.main_window.tabs[1]
    else
        null;
}

fn addInventoryTab(self: *Self) !void {
    const tab = try self.main_window.addEmptyTab(self.session.mode_arena.allocator(), "Inventory");
    const area = try tab.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(tab.allocator(), self, .left);
    try self.updateInventoryTab();
}

/// Rebuilds a list of items
pub fn updateInventoryTab(self: *Self) !void {
    const tab = self.tabWithInventory();
    try w.updateAreaWithItems(
        @ptrCast(@alignCast(tab.scrollable_area.content.underlying)),
        self,
        self.inventory.items,
        formatInventoryLine,
        useCombineDropDescribe,
        describeSelectedItem,
    );
}

fn formatInventoryLine(
    line: *w.TextArea.Line,
    context: *anyopaque,
    item: g.Entity,
) ![]const u8 {
    const self: *Self = @ptrCast(@alignCast(context));
    const sprite = self.session.journal.registry.getUnsafe(item, c.Sprite);
    var buf: [32]u8 = undefined;
    const name = try g.Description.printActualName(&buf, self.session.journal, item);
    const using = if (item.eql(self.equipment.weapon))
        "weapon"
    else if (item.eql(self.equipment.light))
        " light"
    else if (item.eql(self.equipment.ammunition))
        "  ammo"
    else if (item.eql(self.equipment.armor))
        " armor"
    else
        "      ";
    return try std.fmt.bufPrint(line, inventory_line_fmt, .{ sprite.codepoint, name, using });
}

const inventory_line_fmt = std.fmt.comptimePrint(
    "{{u}} {{s:<{d}}}{{s}} ",
    .{w.TabbedWindow.TAB_REGION.cols - 11}, // 12 == ("{u} ".len == 2) + ("weapon ".len == 7) + (2 for borers)
);

fn useCombineDropDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Buttons is helt. Show modal window for {any}", .{item});
    const window = try self.modal_windows.createOnTop(self.session.mode_arena.allocator(), MODAL_WINDOW_REGION);
    const area = try window.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(window.allocator(), self, .center);
    if (self.isEquipped(item)) {
        try area.addOption("Unequip", item, unequipItem, null);
    } else {
        if (self.session.registry.has(item, c.SourceOfLight)) {
            try area.addOption("Use as a light", item, useAsLight, null);
        }
        if (self.session.registry.has(item, c.Weapon)) {
            try area.addOption("Use as a weapon", item, useAsWeapon, null);
        }
        if (self.session.registry.has(item, c.Ammunition)) {
            try area.addOption("Put to quiver", item, putToQuiver, null);
        }
        if (self.session.registry.has(item, c.Armor)) {
            try area.addOption("Wear", item, useAsArmor, null);
        }
        if (self.session.registry.has(item, c.Potion)) {
            try area.addOption("Drink", item, drinkPotion, null);
        } else if (self.session.registry.has(item, c.Consumable)) {
            try area.addOption("Eat", item, consumeFood, null);
        }
    }
    if (self.session.combinations.asIngredient(item)) |_| {
        try area.addOption("Combine", item, combineSelectedItem, null);
    }
    try area.addOption("Drop", item, dropSelectedItem, null);
    try area.addOption("Describe", item, describeSelectedItem, null);
    window.shrinkToContent();
    // keep the main window opened
    return .keep_open;
}

inline fn isEquipped(self: Self, item: g.Entity) bool {
    return item.eql(self.equipment.light) or
        item.eql(self.equipment.weapon) or
        item.eql(self.equipment.armor) or
        item.eql(self.equipment.ammunition);
}

fn unequipItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Unequip the item {d}. (current equipment: {any})", .{ item.id, self.equipment });
    if (item.eql(self.equipment.light))
        self.equipment.light = null;
    if (item.eql(self.equipment.ammunition))
        self.equipment.ammunition = null;
    if (g.meta.isBroken(&self.session.registry, item)) {
        try self.modal_windows.windows.append(
            self.session.mode_arena.allocator(),
            try w.notification(
                self.session.mode_arena.allocator(),
                \\Looks like it is broken and stuck.
                \\You will need to repair  it first.
            ,
                .{ .title = "Oops!", .text_align = .left },
            ),
        );
    } else {
        if (item.eql(self.equipment.weapon))
            self.equipment.weapon = null;
        if (item.eql(self.equipment.armor))
            self.equipment.armor = null;
    }
    try self.updateInventoryTab();
    return .close_window;
}

fn useAsLight(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.equipment.light = item;
    try self.updateInventoryTab();
    return .close_window;
}

fn useAsWeapon(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.equipment.weapon = item;
    if (self.equipment.light == null) {
        if (self.session.registry.get(item, c.SourceOfLight)) |_| {
            self.equipment.light = item;
        }
    }

    try self.updateInventoryTab();
    return .close_window;
}

fn useAsArmor(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.equipment.armor = item;
    try self.updateInventoryTab();
    return .close_window;
}

fn putToQuiver(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.equipment.ammunition = item;
    try self.updateInventoryTab();
    return .close_window;
}

fn consumeFood(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (self.session.registry.get(item, c.Consumable)) |food| {
        log.debug("Consume the item {d} {any}. (current equipment: {any})", .{ item.id, food, self.equipment });
        self.action = .action(.eat, item);
        _ = self.inventory.items.remove(item);
    }
    try self.updateInventoryTab();
    return .close_window;
}

fn drinkPotion(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (self.session.registry.get(item, c.Potion)) |potion| {
        log.debug("Drink the item {d} {any}. (current equipment: {any})", .{ item.id, potion, self.equipment });
        self.action = .action(.drink, item);
        _ = self.inventory.items.remove(item);
    }
    try self.updateInventoryTab();
    return .close_window;
}

fn takeFromPileOrDescribe(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.modal_windows.createOnTop(self.session.mode_arena.allocator(), MODAL_WINDOW_REGION);
    var area = try window.changeContent(w.OptionsArea(g.Entity));
    area.* = .initEmpty(window.allocator(), self, .center);
    try area.addOption("Take", item, takeSelectedItem, null);
    try area.addOption("Describe", item, describeSelectedItem, null);
    window.shrinkToContent();
    return .keep_open;
}

fn addDropTab(self: *Self, drop: g.Entity) !void {
    if (self.main_window.tabs_len < 2) {
        log.debug("Add drop tab for {any}", .{drop});
        const tab = try self.main_window.addEmptyTab(self.session.mode_arena.allocator(), "Drop");
        const area = try tab.changeContent(w.OptionsArea(g.Entity));
        area.* = .initEmpty(tab.allocator(), self, .left);
    }
    try self.updateDropTab(drop);
}

fn updateDropTab(self: *Self, drop: g.Entity) !void {
    self.drop = drop;
    const tab = &self.main_window.tabs[1];
    const options_area: *w.OptionsArea(g.Entity) = @ptrCast(@alignCast(tab.scrollable_area.content.underlying));
    const selected_line = options_area.selected_line;
    options_area.clearRetainingCapacity();
    if (self.session.registry.get(drop, c.Pile)) |pile| {
        var itr = pile.items.iterator();
        while (itr.next()) |item_ptr| {
            try self.addDropOption(options_area, item_ptr.*);
        }
    } else {
        try self.addDropOption(options_area, drop);
    }
    if (options_area.options.items.len > 0) {
        try options_area.selectLine(if (selected_line < options_area.options.items.len)
            selected_line
        else
            options_area.options.items.len - 1);
    }
}

fn addDropOption(
    self: Self,
    options_area: *w.OptionsArea(g.Entity),
    item: g.Entity,
) !void {
    try options_area.addOptionFmt(
        "{u} {f}",
        .{
            self.session.registry.getUnsafe(item, c.Sprite).codepoint,
            g.Description.actualNameFormatter(self.session.journal, item),
        },
        item,
        takeFromPileOrDescribe,
        describeSelectedItem,
    );
}

fn describeSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    log.debug("Show info about item {d}", .{item.id});
    try self.modal_windows.windows.append(
        self.session.mode_arena.allocator(),
        try w.entityDescription(self.session.mode_arena.allocator(), self.session, item),
    );
    // keep the main window opened
    return .keep_open;
}

/// Shows a window with inventory items that can be combined with the selected item.
fn combineSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const window = try self.modal_windows.windows.addOne(self.session.mode_arena.allocator());
    window.* = .init(self.session.mode_arena.allocator(), w.Window.DEFAULT_MAX_REGION);
    var area = try window.changeContent(w.OptionsArea(ResolvedCombination));
    area.* = .initEmpty(window.allocator(), self, .center);
    const ingredient = self.session.combinations.asIngredient(item).?;
    var itr = self.inventory.items.iterator();
    while (itr.next()) |item2| {
        if (self.session.combinations.canBeCombined(ingredient, item2.*)) |resolved_combination| {
            var buffer: w.TextArea.Line = undefined;
            try area.addOption(
                try formatInventoryLine(&buffer, self, item2.*),
                resolved_combination,
                combineItems,
                null,
            );
        }
    }
    window.shrinkToContent();
    return .close_window;
}

fn combineItems(ptr: *anyopaque, _: usize, resolved_combination: ResolvedCombination) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.session.combinations.combine(resolved_combination);
    return .close_window;
}

/// Moves an item from the inventory to the player's position on the level.
/// Add the Drop tab
fn dropSelectedItem(ptr: *anyopaque, _: usize, item: g.Entity) !w.HandleButtonResult {
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
    return .close_window;
}

/// Moves a selected entity from the drop or a pile to the inventory.
/// Removes the Pile tab if the item was the last in the pile.
fn takeSelectedItem(ptr: *anyopaque, _: usize, selected_item: g.Entity) !w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const dropped_entity = self.drop orelse @panic("Attempt to take an undefined item");
    if (self.session.registry.get(selected_item, c.Wallet)) |gold_pile| {
        const wallet = self.session.registry.getUnsafe(self.session.player, c.Wallet);
        wallet.money += gold_pile.money;
        try self.session.registry.removeEntity(selected_item);
    } else {
        try self.inventory.items.add(selected_item);
    }
    if (self.session.registry.get(dropped_entity, c.Pile)) |pile| {
        _ = pile.items.remove(selected_item);
        // Remove the pile only if it is became empty
        if (pile.items.size() == 0) {
            try self.session.registry.removeEntity(dropped_entity);
            self.main_window.removeLastTab();
            self.drop = null;
        } else {
            try self.updateDropTab(dropped_entity);
        }
    } else {
        std.debug.assert(dropped_entity.eql(selected_item));
        try self.session.registry.remove(selected_item, c.Position);
        try self.session.level.removeEntity(selected_item);
        self.main_window.removeLastTab();
    }
    try self.updateInventoryTab();
    return .close_window;
}
