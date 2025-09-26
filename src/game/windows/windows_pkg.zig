//! This is a very simple system of windows. Two key concepts exist:
//! areas and windows. The areas are about managing and drawing a content.
//! The windows are about placing the areas somewhere on screen. Both windows
//! and areas can have a special handlers for buttons. Additionally, windows
//! should handle closing, returning `true` from the button handler.
//!
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

/// A maximal region which can be occupied by the window.
/// This region includes a space for borders.
pub const MAX_REGION = p.Region.init(1, 2, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS - 2);

/// To hide a window something should be drawn inside its region.
/// The easiest way is drawing underlying layer again (for example the whole scene, or a window
/// under the current),but it's on optimal way. Usually we have to particular options:
///  - `from_buffer` - redraw inside the region a content from the inner buffer of the render;
///  - `fill_region` - draw inside the region an empty space.
/// The first one is actual when a window is above the scene, the second - when the window is above
/// another window.
pub const HideMode = enum { from_buffer, fill_region };

pub const ModalWindow = @import("ModalWindow.zig").ModalWindow;
pub const OptionsArea = @import("OptionsArea.zig").OptionsArea;
pub const TextArea = @import("TextArea.zig");
pub const WindowWithTabs = @import("WindowWithTabs.zig");

pub fn scrollingProgress(scrolled_lines: usize, area_height: usize, max_scroll_count: usize) usize {
    var progress = scrolled_lines * area_height / max_scroll_count;
    // Two corner cases for better UX:
    // 1. Move the scroll after the first scrolling
    if (progress == 0 and scrolled_lines > 0) progress += 1;
    // 2. Do not move the scroll to the end until the last possible line is scrolled
    // (progress become == content_height)
    if (progress == area_height - 1 or progress == area_height)
        progress -= 1;
    return progress;
}

/// Example:
/// ```
/// ┌───────────────Title───────────────┐
/// │              Message              │
/// └───────────────────────────────────┘
///═══════════════════════════════════════
///                                Close
/// ```
pub fn notification(alloc: std.mem.Allocator, message: []const u8) !ModalWindow(TextArea) {
    var text_area: TextArea = .empty;
    const line = try text_area.addEmptyLine(alloc);
    const width = MAX_REGION.cols;
    const pad = p.diff(usize, message.len, width) / 2;
    _ = try std.fmt.bufPrint(line[pad..], "{s}", .{message});
    return .{ .area = text_area };
}

/// Approximate example:
/// ```
///               Entity id only in devmode
///                        v
/// ┌────────────────Club(42)───────────┐
/// │ A gnarled piece of wood, scarred  │ 
/// │ from use. Deals blunt damage.     │ 
/// │ Cheap and easy to use.            │ 
/// │                                   │---
/// │ State: sleep                      │ |
/// │ Health: 10/10                     │ |
/// │ Weight: 3                         │ | Only for known entity
/// │ Damage: cutting 2-3               │ |
/// │ Effect:  burning 5                │ |
/// │ Radius of light: 5                │ v
/// └───────────────────────────────────┘---
///═══════════════════════════════════════
///                                Close
/// ```
pub fn entityDescription(
    alloc: std.mem.Allocator,
    session: *const g.GameSession,
    entity: g.Entity,
    dev_mode: bool,
) !ModalWindow(TextArea) {
    // TODO: write test for description of every entity
    var text_area: TextArea = .empty;
    const description = session.registry.get(entity, c.Description);
    const title: []const u8 = if (description) |d| session.getName(entity, d.preset) else "";
    if (dev_mode) {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[1..], "Id: {d}", .{entity.id});
        if (session.registry.get(entity, c.Position)) |position| {
            line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line[1..], "Position: {any}", .{position.place});
        }
        if (session.registry.get(entity, c.EnemyState)) |state| {
            line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line[1..], "State: is {s}", .{@tagName(state.*)});
        }
        if (session.registry.get(entity, c.Health)) |health| {
            line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line[1..], "Health: {d}/{d}", .{ health.current, health.max });
        }
        if (session.registry.get(entity, c.Speed)) |speed| {
            line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line[1..], "Speed: {d}", .{speed.move_points});
        }
        if (session.registry.get(entity, c.Equipment)) |equipment| {
            if (equipment.weapon) |weapon| {
                if (session.registry.get2(weapon, c.Description, c.Damage)) |tuple| {
                    line = try text_area.addEmptyLine(alloc);
                    const name = session.getName(weapon, tuple[0].preset);
                    _ = try std.fmt.bufPrint(line[1..], "Weapon: {s}", .{name});
                    line = try text_area.addEmptyLine(alloc);
                    _ = try std.fmt.bufPrint(
                        line[3..],
                        "Damage: {s} {d}-{d}",
                        .{ @tagName(tuple[1].damage_type), tuple[1].min, tuple[1].max },
                    );
                    if (session.registry.get(weapon, c.Effect)) |effect| {
                        line = try text_area.addEmptyLine(alloc);
                        _ = try std.fmt.bufPrint(
                            line[3..],
                            "Effect: {t} {d}-{d}",
                            .{ effect.effect_type, effect.min, effect.max },
                        );
                    }
                }
            }
            if (equipment.light) |light| {
                if (session.registry.get2(light, c.Description, c.SourceOfLight)) |tuple| {
                    line = try text_area.addEmptyLine(alloc);
                    const name = session.getName(light, tuple[0].preset);
                    _ = try std.fmt.bufPrint(line[1..], "Light: {s} radius {d}", .{ name, tuple[1].radius });
                }
            }
        }
        if (session.registry.get(entity, c.Damage)) |damage| {
            line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(
                line[1..],
                "Damage: {t} {d}-{d}",
                .{ damage.damage_type, damage.min, damage.max },
            );
        }
        if (session.registry.get(entity, c.Effect)) |effect| {
            line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(
                line[1..],
                "Effect: {t} {d}-{d}",
                .{ effect.effect_type, effect.min, effect.max },
            );
        }
        if (session.registry.get(entity, c.SourceOfLight)) |light| {
            line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line[1..], "Radius of light: {d}", .{light.radius});
        }
        if (session.registry.get(entity, c.Weight)) |weight| {
            line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line[1..], "Weight: {d}", .{weight.value});
        }
        line = try text_area.lines.addOne(alloc);
        line.* = @splat('-');
    }
    // A description in form of flat text
    if (description) |descr| {
        for (session.getDescription(entity, descr.preset)) |str| {
            const line = try text_area.addEmptyLine(alloc);
            std.mem.copyForwards(u8, line, str);
        }
    }
    return .{ .area = text_area, .title = title };
}

/// Example:
/// ```
/// ┌──────────────Title───────────────┐
/// │              Option              │
/// │░░░░░░░░░░░░░ Option ░░░░░░░░░░░░░│
/// │              Option              │
/// └──────────────────────────────────┘
///═══════════════════════════════════════
///                          Close Choose
/// ```
pub fn options(
    comptime Item: type,
    owner: *anyopaque,
) ModalWindow(OptionsArea(Item)) {
    return .{ .area = OptionsArea(Item).init(owner, .center) };
}
