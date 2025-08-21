//! Its implementation depends on the Level.
//! The strategy of visibility also affects the strategy of marking visited places on the LevelMap.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.visibility);

pub const VisibilityStrategy = *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility;

/// This global flag is used for cheating
pub var turn_light_on: bool = false;

pub const showNearestWholePlacements: VisibilityStrategy = showNearestPlacements(false);

pub const showNearestPlacementsInLight: VisibilityStrategy = showNearestPlacements(true);

/// Marks as visible the placement with player, and all nearest neighbors with opened doors
/// leads to them. Additionally, this function can checks the light source if the `check_source_of_light`
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

/// Marks as visible the whole placement with the player, and optionally its nearest neighbors, if the player is
/// in the doorway. Ignores the light source. Used in first location.
pub fn showTheCurrentPlacement(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (turn_light_on or level.player_placement.contains(place)) return .visible;

    // check visibility of the nearest placement if the player is in the doorway:
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
/// If the distance more than the radius of the player's source of light,
/// it marks that place as invisible (or known). Used in caves.
pub fn showInRadiusOfSourceOfLight(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (turn_light_on) return .visible;

    var radius: f16 = 1.5;
    // fixme: keep pointer to Equipment of the player in the Level
    if (level.registry.get(level.player, c.Equipment)) |equip| {
        if (equip.light) |light| {
            if (level.registry.get(light, c.SourceOfLight)) |sol| {
                radius = sol.radius;
            }
        }
    }

    if (level.playerPosition().place.distanceTo(place) > radius) {
        log.debug("The place {any} is out of the light radius {d:.2}", .{ place, radius });
        return chechKnownPlaces(level, place);
    } else {
        return .visible;
    }
}

/// Checks known places, to mark invisible, but previously visited places as known.
fn chechKnownPlaces(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (level.isVisited(place)) {
        switch (level.player_placement) {
            // mark invisible everything inside the inner rooms
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
