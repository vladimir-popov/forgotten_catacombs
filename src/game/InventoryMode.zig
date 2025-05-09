//! ```
//! ╔════════════════════════════════════════╗   ╔════════════════════════════════════════╗
//! ║ ┌──────────────Inventory─────────────┐ ║   ║ ┌──────────────Torch <3>─────────────┐ ║
//! ║ │ Magic sword (3:12)             [ ] │ ║   ║ │ Bla...                             │ ║
//! ║ │ T-short [2]                    [x] │ ║   ║ │        bla...                      │ ║
//! ║ │░Torch░░<3>░░░░░░░░░░░░░░░░░░░░░[░]░│ ║   ║ │               bla...               │ ║
//! ║ │ Apple                              │ ║   ║ │                      description   │ ║
//! ║ │ Health portion                     │ ║ > ║ │                                    │ ║
//! ║ │ Club (4:5)                     [ ] │ ║   ║ │ Radius of light: 3                 │ ║
//! ║ │                                    │ ║   ║ │                                    │ ║
//! ║ │                                    │ ║   ║ │                                    │ ║
//! ║ └────────────────────────────────────┘ ║   ║ └────────────────────────────────────┘ ║
//! ║════════════════════════════════════════║   ║════════════════════════════════════════║
//! ║ Close      < drop | use >         Info ║   ║ Use                              Close ║
//! ╚════════════════════════════════════════╝   ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.inventory_mode);

const line_fmt = std.fmt.comptimePrint("{{s:<{d}}}{{s}}", .{g.Window.COLS - 3});

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
        .window = g.Window.init(alloc),
    };
    try self.initInventoryWindow();
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
            } else {
                try self.useItem(self.window.tag - 1);
                try self.initInventoryWindow();
            },
            .a => if (self.window.tag == 0) {
                if (self.window.selected_line) |idx| {
                    try self.initInfoWindow(idx);
                }
            } else {
                try self.initInventoryWindow();
            },
            .right => if (self.window.tag == 0) {
                if (self.window.selected_line) |idx| try self.useItem(idx);
            },
            // .left => if (self.window.selected_line) |idx| try self.dropItem(idx),
            else => {},
        }
        try self.draw();
    }
}

fn draw(self: *InventoryMode) !void {
    try self.session.render.drawWindow(&self.window);
    if (self.window.tag == 0) {
        try self.session.render.drawLeftButton("Close");
        try self.session.render.drawRightButton("Info", false);
        try self.session.render.drawInfo("drop < | > use");
    } else {
        try self.session.render.drawRightButton("Close", false);
        try self.session.render.drawLeftButton("Use");
    }
}

fn initInventoryWindow(self: *InventoryMode) !void {
    self.window.setTitle("Inventory");
    self.window.lines.clearRetainingCapacity();
    self.window.selected_line = 0;
    self.window.tag = 0;
    for (self.inventory.items.items) |item| {
        const line = try self.window.addEmptyLine();
        try self.formatLine(line, item);
    }
}

fn formatLine(self: *InventoryMode, line: *g.Window.Line, item: g.Entity) !void {
    const name = if (self.session.entities.get(item, c.Description)) |desc|
        desc.name()
    else
        "???";
    const using = if (item.eql(self.equipment.weapon) or item.eql(self.equipment.light))
        "[x]"
    else if (self.isTool(item)) "[ ]" else "   ";
    log.debug("{d}:{s} {s}", .{ item.id, name, using });
    _ = try std.fmt.bufPrint(line, line_fmt, .{ name, using });
}

fn isTool(self: *InventoryMode, item: g.Entity) bool {
    return (self.session.entities.get(item, c.Weapon) != null) or
        (self.session.entities.get(item, c.SourceOfLight) != null);
}

fn useItem(self: *InventoryMode, idx: usize) !void {
    std.debug.assert(idx < self.inventory.items.items.len);
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

fn initInfoWindow(self: *InventoryMode, idx: usize) !void {
    std.debug.assert(idx < self.inventory.items.items.len);

    self.window.lines.clearRetainingCapacity();
    self.window.selected_line = null;
    self.window.tag = @truncate(idx + 1);

    const item = self.inventory.items.items[idx];
    log.debug("Show info about item {d}", .{item.id});

    try self.window.info(self.session.entities, item);
}
