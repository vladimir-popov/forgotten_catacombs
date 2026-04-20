//! Its implementation depends on the Level.
//! The strategy of visibility also affects the strategy of marking visited places on the LevelMap.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const cp = g.codepoints;
const d = g.dungeon;
const p = g.primitives;
const u = g.utils;

const log = std.log.scoped(.visibility);

/// This global flag is used for cheating.
pub var turn_light_on: bool = true;

/// Check the visibility status of an entity according to the visibility of the place
/// occupied by the entity.
///
/// If the entity is trap, randomly decides its visibility status, and in case of first time of
/// visibility adds it to known list.
pub fn isEntityVisibile(
    journal: *g.Journal,
    rand: std.Random,
    entity: g.Entity,
    codepoint: g.Codepoint,
    place: p.Point,
    place_visibility: g.Render.Visibility,
    player: g.Entity,
) !bool {
    if (turn_light_on) return true;

    switch (place_visibility) {
        .visible => if (journal.registry.get(entity, c.Trap)) |trap| {
            if (journal.known_entities.contains(entity)) return true;

            const perception: f32 = u.ff32(journal.registry.getUnsafe(player, c.Stats).perception);
            const player_place = journal.registry.getUnsafe(player, c.Position).place;
            const distance: f32 = player_place.distanceTo(place);
            const chance: f32 = (u.ff32(trap.power) + 1.0) / (@max(1.0, distance - perception) * 2.0);
            const is_visible = rand.float(f32) < chance;
            if (is_visible) {
                try journal.markTrapAsKnown(entity);
            }
            return is_visible;
        } else {
            return true;
        },
        .known => return switch (codepoint) {
            // these entities should be always visible after a first meet:
            cp.ladder_up, cp.ladder_down, cp.door_opened, cp.door_closed, cp.teleport => true,
            else => false,
        },
        .invisible => return false,
    }
}

pub const VisibilityStrategy = *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility;

/// Shows nearest placements, including those with opened doors leading to them.
/// If `check_source_of_light` is true, it also checks for a light source.
/// This strategy is used in catacombs.
pub const showNearestWholePlacements: VisibilityStrategy = showNearestPlacements(false);

/// Shows nearest placements in light.
pub const showNearestPlacementsInLight: VisibilityStrategy = showNearestPlacements(true);

/// Marks as visible the placement with the player, and all nearest neighbors with opened doors
/// leading to them. Additionally, this function can check the light source if `check_source_of_light`
/// is true.
/// This strategy is used in catacombs.
fn showNearestPlacements(comptime check_source_of_light: bool) VisibilityStrategy {
    return struct {
        fn visibility(level: *const g.Level, place: p.Point) g.Render.Visibility {
            if (turn_light_on) return .visible;
            if (level.player_placement.contains(place))
                return if (check_source_of_light)
                    showInRadiusOfSourceOfLight(level, place)
                else
                    .visible;

            var doorways = level.player_placement.doorways();
            while (doorways.next()) |door_place| {
                if (level.dungeon.doorwayAt(door_place.*)) |doorway| {
                    if (level.registry.get(doorway.door_id, c.Door)) |door| {
                        if (door.state == .closed) continue;
                        if (doorway.oppositePlacement(level.player_placement)) |placement| {
                            if (placement.contains(place)) return if (check_source_of_light)
                                showInRadiusOfSourceOfLight(level, place)
                            else
                                .visible;
                        }
                    }
                }
            }

            return chechKnownPlaces(level, place);
        }
    }.visibility;
}

/// Marks as visible the whole placement with the player, and optionally its nearest neighbors if the player is
/// in a doorway. Ignores the light source. Used in the first location.
pub fn showTheCurrentPlacement(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (turn_light_on or level.player_placement.contains(place)) return .visible;

    // Check visibility of the nearest placement if the player is in a doorway:
    const player_position = level.playerPosition().place;
    var doorways = level.player_placement.doorways();
    while (doorways.next()) |door_place| {
        if (!door_place.eql(player_position)) continue;
        if (level.dungeon.doorwayAt(door_place.*)) |doorway| {
            if (doorway.oppositePlacement(level.player_placement)) |placement| {
                if (placement.contains(place)) return .visible;
            }
        }
    }

    return chechKnownPlaces(level, place);
}

/// This strategy checks the distance between the player and the checked place.
/// If the distance is greater than the radius of the player's light source,
/// it marks that place as invisible (or known). Used in caves.
pub fn showInRadiusOfSourceOfLight(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (turn_light_on) return .visible;

    _, const radius = g.meta.getLight(level.registry, level.player_equipment);
    const pp = level.playerPosition().place;
    const is_visible = if (radius > 1.0)
        place.isInsideElipse(pp, radius, radius * 0.5)
    else
        place.near8(pp);

    if (is_visible) {
        return .visible;
    } else {
        log.debug("The place {any} is out of the light radius {d:.2}", .{ place, radius });
        return chechKnownPlaces(level, place);
    }
}

/// Checks the place and returns its visibility status as `invisible` or `known`:
/// - all places outside the current placement (where the player is right now) are always invisible;
/// - otherwise the status depends on was the place visited before or not.
fn chechKnownPlaces(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (level.isVisited(place)) {
        switch (level.player_placement) {
            // Mark invisible everything inside the inner rooms
            .area => |area| if (area.isInsideInnerRoom(place)) {
                log.debug("The place {any} is inside the inner room. Mark it as invisible", .{place});
                return .invisible;
            },
            .room => |room| if (room.host_area) |area| if (area.isInsideInnerRoom(place)) {
                log.debug("The place {any} is inside the inner room. Mark it as invisible", .{place});
                return .invisible;
            },
            else => {},
        }
        log.debug("The place {any} is visited. Mark is as known", .{place});
        return .known;
    }
    // log.debug("The place {any} is unknown. Mark it as invisible", .{place});
    return .invisible;
}
