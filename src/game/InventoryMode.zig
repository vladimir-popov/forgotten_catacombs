//! ```
//! ╔════════════════════════════════════════╗   ╔════════════════════════════════════════╗
//! ║ ┌──────────────Inventory─────────────┐ ║   ║ ┌──────────────Torch <3>─────────────┐ ║
//! ║ │ Magic sword (3:12)             [ ] │ ║   ║ │ Bla...                             │ ║
//! ║ │ T-short [2]                    [x] │ ║   ║ │        bla...                      │ ║
//! ║ │░Torch░░<3>░░░░░░░░░░░░░░░░░░░░░[░]░│ ║   ║ │               bla...               │ ║
//! ║ │ Apple                              │ ║   ║ │                      description   │ ║
//! ║ │ Health portion                     │ ║ > ║ │                                    │ ║
//! ║ │ Club (4:5)                     [ ] │ ║   ║ │ Light radius: 3                    │ ║
//! ║ │                                    │ ║   ║ │                                    │ ║
//! ║ │                                    │ ║   ║ │                                    │ ║
//! ║ └────────────────────────────────────┘ ║   ║ └────────────────────────────────────┘ ║
//! ║════════════════════════════════════════║   ║════════════════════════════════════════║
//! ║ Close      < drop | use >         Info ║   ║ Close                              Use ║
//! ╚════════════════════════════════════════╝   ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.inventory);

const InventoryMode = @This();

session: *g.GameSession,
equipment: *c.Equipment,
inventory: *c.Inventory,
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
            .b => if (btn.state == .released) {
                try self.session.play(null);
                return;
            },
            .right => if (self.window.selected_line) |idx| try self.useItem(idx),
            // .left => if (self.window.selected_line) |idx| try self.dropItem(idx),
            else => {},
        }
        try self.draw();
    }
}

fn draw(self: *InventoryMode) !void {
    try self.session.render.drawWindow(&self.window);
    try self.session.render.drawLeftButton("Close");
    try self.session.render.drawRightButton("Info", false);
    try self.session.render.drawInfo("< drop | use >");
}

fn initInventoryWindow(self: *InventoryMode) !void {
    const fmt_mask = std.fmt.comptimePrint("{{s:<{d}}}{{s}}", .{g.Window.COLS - 3});
    std.mem.copyForwards(u8, &self.window.title, "Inventory");
    self.window.selected_line = 0;
    for (self.inventory.items.items) |item| {
        const line = try self.window.addOneLine();
        const name = if (self.session.level.components.getForEntity(item, c.Description)) |desc|
            desc.name
        else
            "???";
        const using = if (self.equipment.weapon == item or self.equipment.light == item)
            "[x]"
        else if (self.isTool(item)) "[ ]" else "   ";
        _ = try std.fmt.bufPrint(line, fmt_mask, .{ name, using });
    }
}

fn isTool(self: *InventoryMode, item: g.Entity) bool {
    return (self.session.level.components.getForEntity(item, c.Weapon) != null) or
        (self.session.level.components.getForEntity(item, c.SourceOfLight) != null);
}

fn useItem(self: *InventoryMode, idx: usize) !void {
    std.debug.assert(idx < self.inventory.items.items.len);
    const item = self.inventory.items.items[idx];
    if (self.equipment.weapon == item) {
        self.equipment.weapon = null;
        return;
    }
    if (self.session.level.components.getForEntity(self.session.level.player, c.Weapon)) |_| {
        self.equipment.weapon = item;
        return;
    }
    if (self.equipment.light == item) {
        self.equipment.light = null;
        return;
    }
    if (self.session.level.components.getForEntity(self.session.level.player, c.SourceOfLight)) |_| {
        self.equipment.light = item;
        return;
    }
}
