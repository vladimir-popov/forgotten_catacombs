//! Set of helpers to get information about entities from a registry.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

pub const Error = error{
    DamageIsNotSpecified,
};

pub fn name(registry: *const g.Registry, entity: g.Entity) []const u8 {
    return if (registry.get(entity, c.Description)) |description|
        g.descriptions.Presets.get(description.preset).name
    else
        "Unknown";
}

pub inline fn isEnemy(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.EnemyState);
}

pub inline fn isItem(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Weight);
}

pub inline fn isWeapon(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Damage);
}

pub inline fn isLight(registry: *const g.Registry, entity: g.Entity) bool {
    return isItem(registry, entity) and registry.has(entity, c.SourceOfLight);
}

pub inline fn isPotion(registry: *const g.Registry, entity: g.Entity) bool {
    return if (registry.get(entity, c.Consumable)) |consumable|
        consumable.consumable_type == .potion
    else
        false;
}

pub fn canEquip(registry: *const g.Registry, item: g.Entity) bool {
    return isItem(registry, item) and
        (registry.has(item, c.Damage) or registry.has(item, c.SourceOfLight));
}

pub fn getRadiusOfLight(registry: *const g.Registry, equipment: *const c.Equipment) f16 {
    if (equipment.light) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return sol.radius;
        }
    }
    return 1.5;
}

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

pub fn describe(
    registry: *const g.Registry,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    is_known: bool,
    text_area: *g.windows.TextArea,
    dev_mode: bool,
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
        try describeItem(registry, alloc, entity, is_known, text_area, dev_mode);
    } else if (isEnemy(registry, entity)) {
        try describeEnemy(registry, alloc, entity, is_known, text_area, dev_mode);
    }
}

fn describeItem(
    registry: *const g.Registry,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    is_known: bool,
    text_area: *g.windows.TextArea,
    dev_mode: bool,
) !void {
    _ = is_known;
    _ = dev_mode;
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
    dev_mode: bool,
) !void {
    _ = is_known;
    _ = dev_mode;
    if (registry.get(enemy, c.Health)) |health| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[1..], "Health: {d}/{d}", .{ health.current, health.max });
    }
    if (registry.get(enemy, c.Speed)) |speed| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[1..], "Speed: {d}", .{speed.move_points});
    }
    if (registry.get(enemy, c.Equipment)) |equipment| {
        try describeEquipment(registry, alloc, equipment, text_area);
    } else if (registry.get(enemy, c.Damage)) |damage| {
        try addWeaponDescription(alloc, damage, registry.get(enemy, c.Effect), text_area, 1);
    }
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

test "Describe torch" {
    // given:
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    const id = try registry.addNewEntity(g.entities.Torch);
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describe(&registry, std.testing.allocator, id, true, &text_area, true);

    // then:
    try expectContent(text_area,
        \\Wooden handle, cloth wrap, burning           
        \\flame. Lasts until the fire dies.            
        \\                                             
        \\ Damage: blunt 2-3                           
        \\ Effect: burning 1-1                         
        \\ Radius of light: 5                          
        \\ Weight: 20                                  
    );
}

fn expectContent(actual: g.windows.TextArea, comptime expectation: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try actual.write(&writer);
    try std.testing.expectEqualStrings(expectation ++ "\n", writer.buffered());
}
