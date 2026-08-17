const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const log = std.log.scoped(.combinations);

const Self = @This();

const MatcherFn = *const fn (registry: *const g.Registry, entity: g.Entity) bool;

pub const Combination = enum {
    refill_lamp,
};

pub const CombinationRule = struct {
    combination: Combination,
    object: MatcherFn,
    subject: MatcherFn,
};

pub const Ingredient = struct {
    rule: CombinationRule,
    object: g.Entity,
};

pub const ResolvedCombination = struct {
    combination: Combination,
    object: g.Entity,
    subject: g.Entity,
};

const rules = [_]CombinationRule{
    .{ .combination = .refill_lamp, .object = isPotion(.oil), .subject = hasPreset(.oil_lamp) },
};

inline fn session(self: *Self) *g.GameSession {
    return @alignCast(@fieldParentPtr("combinations", self));
}

pub fn asIngredient(self: *Self, item: g.Entity) ?Ingredient {
    for (rules) |rule| {
        if (rule.object(&self.session().registry, item))
            return .{ .rule = rule, .object = item };
    }
    return null;
}

pub fn canBeCombined(self: *Self, ingredient: Ingredient, item: g.Entity) ?ResolvedCombination {
    if (ingredient.rule.subject(&self.session().registry, item)) {
        return .{ .combination = ingredient.rule.combination, .object = ingredient.object, .subject = item };
    }
    return null;
}

pub fn combine(self: *Self, resolved_combination: ResolvedCombination) !void {
    switch (resolved_combination.combination) {
        .refill_lamp => {
            const lamp = self.session().registry.getUnsafe(resolved_combination.subject, c.SourceOfLight);
            lamp.charge = lamp.max_charge;
        },
    }
}

pub fn resolveCombination(
    self: *Self,
    item1: g.Entity,
    item2: g.Entity,
) ?ResolvedCombination {
    const registry = &self.session().registry;
    for (rules) |rule| {
        if (rule.object(registry, item1) and rule.subject(registry, item2))
            return .{ .combination = rule.combination, .object = item1, .subject = item2 };
        if (rule.object(registry, item2) and rule.subject(registry, item1))
            return .{ .combination = rule.combination, .object = item2, .subject = item1 };
    }
    return null;
}

fn hasComponent(comptime Component: type) MatcherFn {
    return struct {
        fn matches(registry: *const g.Registry, entity: g.Entity) bool {
            return registry.has(entity, Component);
        }
    }.matches;
}

fn hasPreset(comptime preset: c.Description.Preset.Tag) MatcherFn {
    return struct {
        fn matches(registry: *const g.Registry, entity: g.Entity) bool {
            if (registry.get(entity, c.Description)) |description| {
                return description.preset == preset;
            }
            return false;
        }
    }.matches;
}

fn isPotion(comptime kind: c.Potion) MatcherFn {
    return struct {
        fn matches(registry: *const g.Registry, entity: g.Entity) bool {
            if (registry.get(entity, c.Potion)) |potion| {
                return potion.* == kind;
            }
            return false;
        }
    }.matches;
}
