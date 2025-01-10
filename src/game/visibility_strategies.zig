//! Its implementation depends on the Level.
//! The strategy of visibility also affects the strategy of marking visited places on the LevelMap.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.visibility);

/// This global flag is used for cheating
pub var turn_light_on: bool = false;

/// Marks as visible the whole placement with player, and all nearest neighbors with opened doors
/// leads to them.
///
/// Additionally, this function checks the light source.
pub fn showTheCurrentPlacementInLight(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (turn_light_on) return .visible;
    if (level.player_placement.contains(place)) return showInRadiusOfSourceOfLight(level, place);

    var doorways = level.player_placement.doorways();
    while (doorways.next()) |door_place| {
        if (level.dungeon.doorwayAt(door_place.*)) |doorway| {
            if (level.components.getForEntity(doorway.door_id, c.Door)) |door| {
                if (door.state == .closed) continue;
                if (doorway.oppositePlacement(level.player_placement)) |placement| {
                    if (placement.contains(place)) return showInRadiusOfSourceOfLight(level, place);
                }
            }
        }
    }

    return chechKnownPlaces(level, place);
}

/// Marks as visible the whole placement with player, and optionally its nearest neighbors, if the player is
/// in the doorway.
///
/// Ignores the light source.
pub fn showTheCurrentPlacement(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (turn_light_on or level.player_placement.contains(place)) return .visible;

    // check visibility of the nearest placement if the player is in the doorway:
    const player_position = level.playerPosition().point;
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
/// it marks that place as invisible (or known).
pub fn showInRadiusOfSourceOfLight(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (turn_light_on) return .visible;

    const radius = if (level.components.getForEntity(level.player, c.SourceOfLight)) |sol|
        sol.radius
    else
        2.0;

    if (level.playerPosition().point.distanceTo(place) > radius) {
        log.debug("The place {any} is out of the light radius {d:.2}", .{ place, radius });
        return chechKnownPlaces(level, place);
    } else {
        return .visible;
    }
}

/// Checks known places, to mark invisible, but previously visited places as known.
fn chechKnownPlaces(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (level.map.isVisited(place)) {
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
