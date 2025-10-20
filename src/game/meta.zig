//! Set of helpers to get an information about entities from a registry.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

pub const Error = error{
    DamageIsNotSpecified,
};

/// Returns a string with a name of the entity, or the constant 'Unknown'.
pub fn name(registry: *const g.Registry, entity: g.Entity) []const u8 {
    return if (registry.get(entity, c.Description)) |description|
        g.descriptions.Presets.get(description.preset).name
    else
        "Unknown";
}

/// Any entity with a `EnemyState` is enemy.
pub inline fn isEnemy(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.EnemyState);
}

/// Any entity with weight is item.
pub inline fn isItem(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Weight);
}

/// Any entity with damage is weapon.
pub inline fn isWeapon(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Damage);
}

/// Any entity with a `SourceOfLight` is a light.
pub inline fn isLight(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.SourceOfLight);
}

/// Any consumable entity with `consumable_type` == `.potion` is a potion.
pub inline fn isPotion(registry: *const g.Registry, entity: g.Entity) bool {
    return if (registry.get(entity, c.Consumable)) |consumable|
        consumable.consumable_type == .potion
    else
        false;
}

/// Only weapon and source of light can be equipped.
pub fn canEquip(registry: *const g.Registry, item: g.Entity) bool {
    return (registry.has(item, c.Damage) or registry.has(item, c.SourceOfLight));
}

/// Returns the radius of the light as a maximal radius of all equipped sources of the light.
pub fn getRadiusOfLight(registry: *const g.Registry, equipment: *const c.Equipment) f16 {
    if (equipment.light) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return sol.radius;
        }
    }
    return 1.5;
}

/// Returns a `Damage` component and optional `Effect` of the currently used weapon.
/// The `actor` must be a player or an enemy,  otherwise the `DamageIsNotSpecified` will be returned.
pub fn getDamage(registry: *const g.Registry, actor: g.Entity) Error!struct { *c.Damage, ?*c.Effect } {
    // creatures can damage directly (rat's tooth as example)
    if (registry.get(actor, c.Damage)) |damage| {
        return .{ damage, registry.get(actor, c.Effect) };
    }
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.weapon) |weapon| {
            if (registry.get(weapon, c.Damage)) |damage| {
                return .{ damage, registry.get(weapon, c.Effect) };
            }
        }
    }
    return error.DamageIsNotSpecified;
}

/// Builds an actual description of the entity, and writes it to the text_area.
pub fn describe(
    registry: *const g.Registry,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    is_known: bool,
    text_area: *g.windows.TextArea,
) !void {
    const description = if (registry.get(entity, c.Description)) |descr|
        g.descriptions.Presets.get(descr.preset).description
    else
        &.{};
    for (description) |str| {
        var line = try text_area.addEmptyLine(alloc);
        @memmove(line[0..str.len], str);
    }
    _ = try text_area.addEmptyLine(alloc);
    if (isItem(registry, entity)) {
        try describeItem(registry, alloc, entity, is_known, text_area);
    } else if (isEnemy(registry, entity)) {
        try describeEnemy(registry, alloc, entity, is_known, text_area);
    }
}

fn describeItem(
    registry: *const g.Registry,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    is_known: bool,
    text_area: *g.windows.TextArea,
) !void {
    _ = is_known;
    if (registry.get(entity, c.Damage)) |damage| {
        try addWeaponDescription(alloc, damage, registry.get(entity, c.Effect), text_area, 0);
    }
    if (registry.get(entity, c.SourceOfLight)) |light| {
        const line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Radius of light: {d}", .{light.radius});
    }
    if (registry.get(entity, c.Weight)) |weight| {
        const line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Weight: {d}", .{weight.value});
    }
}

fn describeEnemy(
    registry: *const g.Registry,
    alloc: std.mem.Allocator,
    enemy: g.Entity,
    is_known: bool,
    text_area: *g.windows.TextArea,
) !void {
    if (is_known) {
        if (registry.get(enemy, c.Health)) |health| {
            const line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line, "Health: {d}/{d}", .{ health.current, health.max });
        }
        if (registry.get(enemy, c.Equipment)) |equipment| {
            try describeEquipment(registry, alloc, equipment, text_area);
        } else if (registry.get(enemy, c.Damage)) |damage| {
            try addWeaponDescription(alloc, damage, registry.get(enemy, c.Effect), text_area, 0);
        }
        if (registry.get(enemy, c.Speed)) |speed| {
            _ = try text_area.addEmptyLine(alloc);
            // | Too slow | Slow | Not so fast | Fast | Very fast |
            //            |      |             |      |
            //          +10     +5           Normal  -5
            const diff: i16 = speed.move_points - c.Speed.default.move_points;
            const line = try text_area.addEmptyLine(alloc);
            if (diff >= 0) {
                if (diff < 5)
                    _ = try std.fmt.bufPrint(line, "Not too fast.", .{})
                else if (diff < 10)
                    _ = try std.fmt.bufPrint(line, "Slow.", .{})
                else
                    _ = try std.fmt.bufPrint(line, "Too slow.", .{});
            } else {
                if (diff > -5)
                    _ = try std.fmt.bufPrint(line, "Fast.", .{})
                else
                    _ = try std.fmt.bufPrint(line, "Very fast.", .{});
            }
        }
    } else {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[0..], "Who knows what to expect from this", .{});
        line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[0..], "creature?", .{});
    }
}

test "Describe an unknown rat" {
    // given:
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    const id = try registry.addNewEntity(g.entities.rat(.{ .row = 1, .col = 1 }));
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describe(&registry, std.testing.allocator, id, false, &text_area);

    // then:
    try expectContent(text_area,
        \\A big, nasty rat with vicious eyes
        \\that thrives in dark corners and
        \\forgotten cellars.
        \\
        \\Who knows what to expect from this
        \\creature?
    );
}

test "Describe a known rat" {
    // given:
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    const id = try registry.addNewEntity(g.entities.rat(.{ .row = 1, .col = 1 }));
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describe(&registry, std.testing.allocator, id, true, &text_area);

    // then:
    try expectContent(text_area,
        \\A big, nasty rat with vicious eyes
        \\that thrives in dark corners and
        \\forgotten cellars.
        \\
        \\Health: 10/10
        \\Damage: thrusting 1-3
        \\
        \\Not too fast.
    );
}

fn describeEquipment(
    registry: *const g.Registry,
    alloc: std.mem.Allocator,
    equipment: *const c.Equipment,
    text_area: *g.windows.TextArea,
) !void {
    if (equipment.weapon) |weapon| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[1..], "Equiped weapon: {s}", .{g.meta.name(registry, weapon)});
        try addWeaponDescription(
            alloc,
            registry.getUnsafe(weapon, c.Damage),
            registry.get(weapon, c.Effect),
            text_area,
            3,
        );
    }
    var line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line[1..], "Radius of light: {d}", .{g.meta.getRadiusOfLight(registry, equipment)});
}

fn addWeaponDescription(
    alloc: std.mem.Allocator,
    damage: *const c.Damage,
    maybe_effect: ?*const c.Effect,
    text_area: *g.windows.TextArea,
    pad: usize,
) !void {
    var line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(
        line[pad..],
        "Damage: {t} {d}-{d}",
        .{ damage.damage_type, damage.min, damage.max },
    );
    if (maybe_effect) |effect| {
        line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(
            line[pad..],
            "Effect: {t} {d}-{d}",
            .{ effect.effect_type, effect.min, effect.max },
        );
    }
}

test "Describe a torch" {
    // given:
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    const id = try registry.addNewEntity(g.entities.Torch);
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describe(&registry, std.testing.allocator, id, true, &text_area);

    // then:
    try expectContent(text_area,
        \\Wooden handle, cloth wrap, burning
        \\flame. Lasts until the fire dies.
        \\
        \\Damage: blunt 2-3
        \\Effect: burning 1-1
        \\Radius of light: 5
        \\Weight: 20
    );
}

fn expectContent(actual: g.windows.TextArea, comptime expectation: []const u8) !void {
    errdefer {
        var buffer: [1024]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        actual.write(&writer) catch unreachable;
        std.debug.print("\nThe actual content was:\n--------------\n{s}\n--------------", .{buffer});
    }
    var itr = std.mem.splitScalar(u8, expectation, '\n');
    var i: usize = 0;
    while (itr.next()) |line| {
        try std.testing.expectEqualStrings(line, std.mem.trimEnd(u8, &actual.lines.items[i], " \n"));
        i += 1;
    }
}
