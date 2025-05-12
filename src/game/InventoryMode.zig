//! ```
//! ╔════════════════════════════════════════╗   ╔════════════════════════════════════════╗
//! ║                Inventory               ║   ║                                        ║
//! ║\ Magic sword (3:12)                [ ] ║   ║                                        ║
//! ║[ T-short [2]                       [x] ║   ║ ┌──────────────Torch <3>─────────────┐ ║
//! ║/░Torch░░<3>░░░░░░░░░░░░░░░░░░░░░░░░[░]░║   ║ │ Bla...                             │ ║
//! ║, Apple                                 ║   ║ │        bla...                      │ ║
//! ║! Health portion                        ║ > ║ │               bla...               │ ║
//! ║\ Club (4:5)                        [ ] ║   ║ │                      description   │ ║
//! ║                                        ║   ║ │                                    │ ║
//! ║                                        ║   ║ │ Radius of light: 3                 │ ║                                     ║
//! ║                                        ║   ║ └────────────────────────────────────┘ ║
//! ║                                        ║   ║                                        ║
//! ║ Close      < drop | use >         Info ║   ║                                  Close ║
//! ╚════════════════════════════════════════╝   ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.inventory_mode);

const InventoryMode = @This();

session: *g.GameSession,
equipment: *c.Equipment,
inventory: *c.Inventory,
/// tag == 0 means inventory window;
/// any other values mean a window with info about an item from the inventory with idx == tag - 1
window: g.Window,

pub fn init(
    self: *InventoryMode,
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    equipment: *c.Equipment,
    inventory: *c.Inventory,
) !void {
    self.* = .{
        .session = session,
        .equipment = equipment,
        .inventory = inventory,
        .window = g.Window.fullScreen(alloc),
    };
    try self.initInventoryWindow(if (self.inventory.items.items.len > 0) 0 else null);
    try self.draw();
}

pub fn deinit(self: *InventoryMode) void {
    self.window.deinit();
}

pub fn tick(self: *InventoryMode) !void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.game_button) {
            .up => self.window.selectPreviousLine(),
            .down => self.window.selectNextLine(),
            .b => if (self.window.tag == 0) {
                try self.session.play(null);
                return;
            },
            .a => if (self.window.tag == 0) {
                if (self.window.selected_line) |idx| {
                    try self.initInfoWindow(idx);
                }
            } else {
                try self.initInventoryWindow(self.window.tag - 1);
            },
            .right => if (self.window.tag == 0) {
                if (self.window.selected_line) |idx| try self.useItem(idx);
            },
            .left => if (self.window.tag == 0) {
                if (self.window.selected_line) |idx|
                    try self.dropItem(idx, self.session.level.playerPosition().place);
            },
        }
        try self.draw();
    }
}

fn draw(self: *InventoryMode) !void {
    try self.session.render.cleanInfo();
    try self.session.render.drawWindow(&self.window);
    if (self.window.tag == 0) {
        try self.session.render.drawLeftButton("Close");
        if (self.inventory.items.items.len > 0) {
            try self.session.render.drawRightButton("Info", false);
            try self.session.render.drawInfo("  drop < | > use");
        } else {
            try self.session.render.hideRightButton();
        }
    } else {
        try self.session.render.hideLeftButton();
        try self.session.render.drawRightButton("Close", false);
    }
}

fn initInventoryWindow(self: *InventoryMode, idx: ?usize) !void {
    self.window.setTitle("Inventory");
    self.window.lines.clearRetainingCapacity();
    self.window.selected_line = idx;
    self.window.tag = 0;
    self.window.mode = .full_screen;

    for (self.inventory.items.items) |item| {
        const line = try self.window.addEmptyLine();
        try self.formatLine(line, item);
    }
}

const line_fmt = std.fmt.comptimePrint("{{u}} {{s:<{d}}}{{s}}", .{g.Window.MAX_LINE_SYMBOLS - 5});

fn formatLine(self: *InventoryMode, line: *g.Window.Line, item: g.Entity) !void {
    const sprite = self.session.entities.getUnsafe(item, c.Sprite);
    const name = if (self.session.entities.get(item, c.Description)) |desc|
        desc.name()
    else
        "???";
    const using = if (item.eql(self.equipment.weapon) or item.eql(self.equipment.light))
        "[x]"
    else if (self.isTool(item)) "[ ]" else "   ";
    log.debug("{d}: {u} {s} {s}", .{ item.id, sprite.codepoint, name, using });
    _ = try std.fmt.bufPrint(line, line_fmt, .{ sprite.codepoint, name, using });
}

fn isTool(self: *InventoryMode, item: g.Entity) bool {
    return (self.session.entities.get(item, c.Weapon) != null) or
        (self.session.entities.get(item, c.SourceOfLight) != null);
}

fn useItem(self: *InventoryMode, idx: usize) !void {
    if (idx >= self.inventory.items.items.len) return;

    const item = self.inventory.items.items[idx];
    log.debug("Use item {d} ({any})", .{ item.id, self.equipment });

    if (item.eql(self.equipment.weapon)) {
        self.equipment.weapon = null;
    } else if (self.session.entities.get(item, c.Weapon)) |_| {
        self.equipment.weapon = item;
    }
    if (item.eql(self.equipment.light)) {
        self.equipment.light = null;
    } else if (self.session.entities.get(item, c.SourceOfLight)) |_| {
        self.equipment.light = item;
    }

    try self.formatLine(&self.window.lines.items[idx], item);
}

fn dropItem(self: *InventoryMode, idx: usize, place: p.Point) !void {
    if (idx >= self.inventory.items.items.len) return;

    const item = self.inventory.items.orderedRemove(idx);
    _ = self.window.lines.orderedRemove(idx);
    if (self.window.lines.items.len == 0) {
        self.window.selected_line = null;
    } else if (idx >= self.inventory.items.items.len) {
        self.window.selected_line = self.inventory.items.items.len - 1;
    }

    log.debug("Drop item {d} at {any}", .{ item.id, place });

    if (item.eql(self.equipment.weapon)) {
        self.equipment.weapon = null;
    }
    if (item.eql(self.equipment.light)) {
        self.equipment.light = null;
    }
    try self.session.level.addEntityAtPlace(item, place);
}

fn initInfoWindow(self: *InventoryMode, idx: usize) !void {
    std.debug.assert(idx < self.inventory.items.items.len);

    self.window.lines.clearRetainingCapacity();
    self.window.selected_line = null;
    self.window.tag = @truncate(idx + 1);
    self.window.mode = .modal;

    const item = self.inventory.items.items[idx];
    log.debug("Show info about item {d}", .{item.id});

    try self.window.info(self.session.entities, item, self.session.runtime.isDevMode());
}
